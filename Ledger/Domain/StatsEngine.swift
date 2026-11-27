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

    static func includesExpense(
        _ txn: Txn,
        caliber: StatsCaliber,
        openClaims: Set<UUID>,
        claimsById: [UUID: Claim] = [:]
    ) -> Bool {
        guard txn.type == .expense else { return false }
        // 报销到账时补记的差额是个人消费，不是新的现金支出，也不是新的垫付。
        if txn.source == .reimbursement { return caliber == .personal }
        switch caliber {
        case .cashFlow:
            return true
        case .personal:
            guard txn.isReimbursable, let claimId = txn.claimId else { return true }
            // 待报销与已到账的原始垫付都不算个人消费；报不掉而关闭的才重新计入。
            if openClaims.contains(claimId) || claimsById[claimId]?.status == .reimbursed {
                return false
            }
            return true
        case .advance:
            return txn.isReimbursable
        }
    }

    /// 只有原支出本身计入当前口径时，退款才应冲减该口径。
    static func includesRefund(
        _ txn: Txn,
        caliber: StatsCaliber,
        allTxns: [Txn],
        openClaims: Set<UUID>,
        claimsById: [UUID: Claim] = [:]
    ) -> Bool {
        guard RefundService.isRefund(txn), let originalId = txn.refundOfTxnId else { return false }
        guard let original = allTxns.first(where: { $0.id == originalId && $0.deletedAt == nil }) else { return false }
        return includesExpense(original, caliber: caliber, openClaims: openClaims, claimsById: claimsById)
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
        let claimsById = Dictionary(uniqueKeysWithValues: claims.map { ($0.id, $0) })
        var income: Int64 = 0
        var expense: Int64 = 0
        var refunded: Int64 = 0
        var pending: Int64 = 0

        for txn in txns where txn.deletedAt == nil && range.contains(txn.occurredAt) {
            if includesIncome(txn, caliber: caliber) {
                income += txn.amountMinor
            }
            if includesExpense(txn, caliber: caliber, openClaims: open, claimsById: claimsById) {
                expense += txn.amountMinor
            }
            if includesRefund(txn, caliber: caliber, allTxns: txns, openClaims: open, claimsById: claimsById) {
                refunded += txn.amountMinor
            }
            if txn.type == .expense, txn.isReimbursable,
               let claimId = txn.claimId, open.contains(claimId) {
                pending += txn.amountMinor
            }
        }

        // 待报销金额也要扣除已经发生的退款，避免把已退回的钱继续算作在途垫付。
        if caliber == .personal {
            for txn in txns where txn.deletedAt == nil && RefundService.isRefund(txn) {
                guard let originalId = txn.refundOfTxnId,
                      let original = txns.first(where: { $0.id == originalId && $0.deletedAt == nil }),
                      range.contains(original.occurredAt),
                      original.isReimbursable,
                      let claimId = original.claimId,
                      open.contains(claimId) else { continue }
                pending -= txn.amountMinor
            }
        }
        pending = max(0, pending)

        // 退款是否冲减取决于原支出是否属于当前口径，跨期退款仍在到账月冲减。
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
        let claimsById = Dictionary(uniqueKeysWithValues: claims.map { ($0.id, $0) })
        var totals: [UUID: (amount: Int64, count: Int)] = [:]
        var unknownAmount: Int64 = 0
        var unknownCount = 0

        for txn in txns where txn.deletedAt == nil && range.contains(txn.occurredAt) {
            guard includesExpense(txn, caliber: caliber, openClaims: open, claimsById: claimsById) else { continue }
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
            for txn in txns where txn.deletedAt == nil && range.contains(txn.occurredAt) && includesRefund(txn, caliber: caliber, allTxns: txns, openClaims: open, claimsById: claimsById) {
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

    /// 最近 N 个月的收支趋势，与当前统计页选择的口径保持一致。
    static func byMonth(
        months: Int,
        endingAt: Date,
        txns: [Txn],
        claims: [Claim] = [],
        caliber: StatsCaliber = .cashFlow
    ) -> [MonthBucket] {
        guard months > 0 else { return [] }
        var buckets: [MonthBucket] = []
        let calendar = AppCalendar.gregorian
        let anchor = AppCalendar.startOfMonth(endingAt)

        for offset in stride(from: months - 1, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: anchor) else { continue }
            let summary = summary(
                range: AppCalendar.monthInterval(containing: monthStart),
                caliber: caliber,
                txns: txns,
                claims: claims
            )
            buckets.append(
                MonthBucket(
                    id: AppCalendar.monthKey(monthStart),
                    monthStart: monthStart,
                    incomeMinor: summary.incomeMinor,
                    expenseMinor: summary.expenseMinor
                )
            )
        }
        return buckets
    }
}
