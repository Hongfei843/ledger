import Foundation

enum StatsCaliber: String, CaseIterable, Identifiable {
    case cashFlow
    case personal
    case advance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cashFlow: return "现金流"
        case .personal: return "个人消费"
        case .advance: return "垫付"
        }
    }
}

struct StatsSummary {
    let incomeMinor: Int64
    let expenseMinor: Int64
    let pendingMinor: Int64

    var balanceMinor: Int64 { incomeMinor - expenseMinor }

    var savingRate: Double {
        guard incomeMinor > 0 else { return 0 }
        return Double(balanceMinor) / Double(incomeMinor)
    }
}

struct CategorySlice: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let colorHex: String
    let amountMinor: Int64
    let count: Int
}

struct MonthBucket: Identifiable {
    let id: String
    let monthStart: Date
    let incomeMinor: Int64
    let expenseMinor: Int64
}

/// 统计引擎：所有口径由同一个入口按参数切换，不写多套查询。
enum StatsEngine {
    /// 未分类聚合用的稳定 id，保证视图 diff 稳定
    static let uncategorizedId = UUID(uuidString: "00000000-0000-0000-0000-0000000F0F0F") ?? UUID()

    static func openClaimIds(claims: [Claim]) -> Set<UUID> {
        var result: Set<UUID> = []
        for claim in claims where claim.deletedAt == nil {
            if claim.status == .draft || claim.status == .submitted {
                result.insert(claim.id)
            }
        }
        return result
    }

    static func includesExpense(_ txn: Txn, caliber: StatsCaliber, openClaims: Set<UUID>) -> Bool {
        guard txn.type == .expense else { return false }
        switch caliber {
        case .cashFlow:
            return true
        case .personal:
            if txn.isReimbursable, let claimId = txn.claimId, openClaims.contains(claimId) {
                return false
            }
            return true
        case .advance:
            return txn.isReimbursable
        }
    }

    static func includesIncome(_ txn: Txn, caliber: StatsCaliber) -> Bool {
        // 退款不算收入：它是原支出的冲减
        guard txn.type == .income, !RefundService.isRefund(txn) else { return false }
        switch caliber {
        case .cashFlow:
            return true
        case .personal:
            // 报销到账不是个人收入
            return txn.claimId == nil
        case .advance:
            return txn.claimId != nil
        }
    }

    static func summary(
        range: DateInterval,
        caliber: StatsCaliber,
        txns: [Txn],
        claims: [Claim]
    ) -> StatsSummary {
        let open = openClaimIds(claims: claims)
        var income: Int64 = 0
        var expense: Int64 = 0
        var refunded: Int64 = 0
        var pending: Int64 = 0

        for txn in txns where txn.deletedAt == nil && range.contains(txn.occurredAt) {
            if includesIncome(txn, caliber: caliber) {
                income += txn.amountMinor
            }
            if includesExpense(txn, caliber: caliber, openClaims: open) {
                expense += txn.amountMinor
            }
            if RefundService.isRefund(txn) {
                refunded += txn.amountMinor
            }
            if txn.type == .expense, txn.isReimbursable,
               let claimId = txn.claimId, open.contains(claimId) {
                pending += txn.amountMinor
            }
        }

        // 退款冲减支出（垫付口径只核对垫付与到账，不做冲减）
        if caliber != .advance {
            expense = RefundService.netExpense(expenseMinor: expense, refundMinor: refunded)
        }

        return StatsSummary(incomeMinor: income, expenseMinor: expense, pendingMinor: pending)
    }

    static func byCategory(
        range: DateInterval,
        caliber: StatsCaliber,
        txns: [Txn],
        claims: [Claim],
        categories: [Category]
    ) -> [CategorySlice] {
        let open = openClaimIds(claims: claims)
        var totals: [UUID: (amount: Int64, count: Int)] = [:]
        var unknownAmount: Int64 = 0
        var unknownCount = 0

        for txn in txns where txn.deletedAt == nil && range.contains(txn.occurredAt) {
            guard includesExpense(txn, caliber: caliber, openClaims: open) else { continue }
            if let categoryId = txn.categoryId {
                let current = totals[categoryId] ?? (0, 0)
                totals[categoryId] = (current.amount + txn.amountMinor, current.count + 1)
            } else {
                unknownAmount += txn.amountMinor
                unknownCount += 1
            }
        }

        // 退款冲减原分类（退款流水继承了原支出的分类），垫付口径不冲减
        if caliber != .advance {
            for txn in txns where txn.deletedAt == nil && range.contains(txn.occurredAt) && RefundService.isRefund(txn) {
                if let categoryId = txn.categoryId, let current = totals[categoryId] {
                    totals[categoryId] = (current.amount - txn.amountMinor, current.count)
                } else {
                    unknownAmount -= txn.amountMinor
                }
            }
        }

        var slices: [CategorySlice] = []
        for (categoryId, value) in totals {
            guard value.amount > 0, let category = categories.first(where: { $0.id == categoryId }) else { continue }
            slices.append(
                CategorySlice(
                    id: categoryId,
                    name: category.name,
                    emoji: category.iconEmoji,
                    colorHex: category.colorHex,
                    amountMinor: value.amount,
                    count: value.count
                )
            )
        }

        if unknownCount > 0, unknownAmount > 0 {
            slices.append(
                CategorySlice(
                    id: uncategorizedId,
                    name: "未分类",
                    emoji: "❓",
                    colorHex: "999999",
                    amountMinor: unknownAmount,
                    count: unknownCount
                )
            )
        }

        return slices.sorted { $0.amountMinor > $1.amountMinor }
    }

    /// 最近 N 个月的收支（用于趋势图）；退款同样冲减支出、不计收入
    static func byMonth(months: Int, endingAt: Date, txns: [Txn]) -> [MonthBucket] {
        guard months > 0 else { return [] }
        var buckets: [MonthBucket] = []
        let calendar = AppCalendar.gregorian
        let anchor = AppCalendar.startOfMonth(endingAt)

        for offset in stride(from: months - 1, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: anchor) else { continue }
            let interval = AppCalendar.monthInterval(containing: monthStart)
            var income: Int64 = 0
            var expense: Int64 = 0
            var refunded: Int64 = 0

            for txn in txns where txn.deletedAt == nil && interval.contains(txn.occurredAt) {
                if txn.type == .income && !RefundService.isRefund(txn) { income += txn.amountMinor }
                if txn.type == .expense { expense += txn.amountMinor }
                if RefundService.isRefund(txn) { refunded += txn.amountMinor }
            }
            expense = RefundService.netExpense(expenseMinor: expense, refundMinor: refunded)

            buckets.append(
                MonthBucket(
                    id: AppCalendar.monthKey(monthStart),
                    monthStart: monthStart,
                    incomeMinor: income,
                    expenseMinor: expense
                )
            )
        }
        return buckets
    }
}
