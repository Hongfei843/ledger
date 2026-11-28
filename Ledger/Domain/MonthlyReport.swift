import Foundation

/// 一个月度报告的条目/汇总（纯数据，方便单测）。
struct MonthlyReportCategory: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let colorHex: String
    let amountMinor: Int64
    /// 占当月净支出的比例（0...1）
    let share: Double
}

struct MonthlyReportItem: Identifiable {
    let id: UUID
    let payee: String
    let amountMinor: Int64
    let occurredAt: Date
    let categoryName: String
}

struct MonthlyReportDay: Identifiable {
    let id: Date
    let day: Date
    let expenseMinor: Int64
    let incomeMinor: Int64
}

struct MonthlyReport {
    let monthStart: Date
    let txnsCount: Int
    let incomeMinor: Int64
    let expenseMinor: Int64
    let previousIncomeMinor: Int64
    let previousExpenseMinor: Int64
    let categories: [MonthlyReportCategory]
    /// 分类合计与本月支出的差额：负数表示有退款已冲减支出、但该分类本月已被冲成 0，无法展示。
    /// 不变式：分类合计 + 该值 == 本月支出。
    let refundOffsetMinor: Int64
    let topExpenses: [MonthlyReportItem]
    let days: [MonthlyReportDay]

    var netMinor: Int64 { incomeMinor - expenseMinor }
    var hasData: Bool { incomeMinor > 0 || expenseMinor > 0 }
    /// 上月是否真的没有任何流水（用于区分「上月无数据」和「上月没有同类金额」）
    var previousHasData: Bool { previousIncomeMinor > 0 || previousExpenseMinor > 0 }

    /// 环比（百分比，四舍五入）；上期没有数据时为 nil
    var expenseChangePercent: Int? { Self.change(current: expenseMinor, previous: previousExpenseMinor) }
    var incomeChangePercent: Int? { Self.change(current: incomeMinor, previous: previousIncomeMinor) }

    /// 储蓄率：结余 / 收入（百分比）
    var savingsRatePercent: Int? {
        guard incomeMinor > 0 else { return nil }
        return Int((Double(netMinor) / Double(incomeMinor) * 100).rounded())
    }

    static func change(current: Int64, previous: Int64) -> Int? {
        guard previous > 0 else { return nil }
        return Int(((Double(current) - Double(previous)) / Double(previous) * 100).rounded())
    }
}

enum MonthlyReportBuilder {
    /// 未分类流水归到这个固定 ID，展示为「未分类」
    static let unclassifiedId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    static func build(
        monthAnchor: Date,
        txns: [Txn],
        categories: [Category],
        calendar: Calendar = AppCalendar.gregorian
    ) -> MonthlyReport {
        let interval = AppCalendar.monthInterval(containing: monthAnchor)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: interval.start) ?? interval.start
        let previousInterval = AppCalendar.monthInterval(containing: previousStart)

        let live = txns.filter { $0.deletedAt == nil }
        let inMonth = live.filter { interval.contains($0.occurredAt) }

        let totals = computeTotals(txns: inMonth)
        let previousTotals = computeTotals(txns: live.filter { previousInterval.contains($0.occurredAt) })

        let categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        var buckets: [UUID: Int64] = [:]
        for txn in inMonth where txn.type == .expense && txn.source != .reimbursement {
            buckets[txn.categoryId ?? unclassifiedId, default: 0] += txn.amountMinor
        }
        // 退款冲减原分类
        let byId = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        for txn in inMonth where RefundService.isRefund(txn) {
            let originalCategory = txn.refundOfTxnId.flatMap { byId[$0]?.categoryId }
            buckets[originalCategory ?? unclassifiedId, default: 0] -= txn.amountMinor
        }

        // 占比分母取「毛支出合计」与「本月净支出」中的较大者：
        // 正常两者相等（合计 100%）；退款把某分类冲成负数时，不会出现 300% 这种占比。
        let positiveTotal = buckets.values.filter { $0 > 0 }.reduce(Int64(0)) { $0 + $1 }
        let shareBase = max(totals.expense, positiveTotal)

        let rankedAll = buckets
            .map { id, amount -> MonthlyReportCategory in
                let category = categoryById[id]
                let displayAmount = max(0, amount)
                let share = shareBase > 0 ? Double(displayAmount) / Double(shareBase) : 0
                return MonthlyReportCategory(
                    id: id,
                    name: category?.name ?? "未分类",
                    emoji: category?.iconEmoji ?? "📦",
                    colorHex: category?.colorHex ?? "8E8E93",
                    amountMinor: displayAmount,
                    share: min(1, share)
                )
            }
            .filter { $0.amountMinor > 0 }
            .sorted { $0.amountMinor > $1.amountMinor }

        let rankedSum = rankedAll.reduce(Int64(0)) { $0 + $1.amountMinor }
        let ranked = Array(rankedAll.prefix(8))

        let topExpenses = inMonth
            .filter { $0.type == .expense && $0.source != .reimbursement }
            .sorted { $0.amountMinor > $1.amountMinor }
            .prefix(5)
            .map { txn in
                MonthlyReportItem(
                    id: txn.id,
                    payee: txn.payee?.isEmpty == false ? (txn.payee ?? "") : (categoryById[txn.categoryId ?? UUID()]?.name ?? "支出"),
                    amountMinor: txn.amountMinor,
                    occurredAt: txn.occurredAt,
                    categoryName: categoryById[txn.categoryId ?? UUID()]?.name ?? "未分类"
                )
            }

        var dayExpense: [Date: Int64] = [:]
        var dayIncome: [Date: Int64] = [:]
        for txn in inMonth {
            let day = calendar.startOfDay(for: txn.occurredAt)
            switch txn.type {
            case .expense where txn.source != .reimbursement:
                dayExpense[day, default: 0] += txn.amountMinor
            case .income where RefundService.isRefund(txn):
                dayExpense[day, default: 0] -= txn.amountMinor
            case .income:
                dayIncome[day, default: 0] += txn.amountMinor
            default:
                break
            }
        }
        var days: [MonthlyReportDay] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            days.append(
                MonthlyReportDay(
                    id: cursor,
                    day: cursor,
                    expenseMinor: dayExpense[cursor] ?? 0,
                    incomeMinor: dayIncome[cursor] ?? 0
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return MonthlyReport(
            monthStart: interval.start,
            txnsCount: inMonth.count,
            incomeMinor: totals.income,
            expenseMinor: totals.expense,
            previousIncomeMinor: previousTotals.income,
            previousExpenseMinor: previousTotals.expense,
            categories: ranked,
            refundOffsetMinor: totals.expense - rankedSum,
            topExpenses: topExpenses,
            days: days
        )
    }

    private static func computeTotals(txns: [Txn]) -> (income: Int64, expense: Int64) {
        let gross = txns.filter { $0.type == .expense && $0.source != .reimbursement }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let refund = txns.filter { RefundService.isRefund($0) }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let income = txns
            .filter { $0.type == .income && !RefundService.isRefund($0) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
        return (income, RefundService.netExpense(expenseMinor: gross, refundMinor: refund))
    }
}
