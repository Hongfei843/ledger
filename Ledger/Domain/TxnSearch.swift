import Foundation

/// 搜索的时间范围
enum SearchDateScope: String, CaseIterable, Identifiable {
    case all
    case thisMonth
    case last30Days
    case thisYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部时间"
        case .thisMonth: return "本月"
        case .last30Days: return "近 30 天"
        case .thisYear: return "今年"
        }
    }
}

/// 搜索条件：把过滤逻辑从视图里抽出来，方便单测。
struct TxnSearchCriteria: Equatable {
    var keyword: String = ""
    var types: Set<TxnType> = []
    var accountId: UUID?
    var categoryId: UUID?
    var onlyReimbursable = false
    var onlyRefunds = false
    var minAmountMinor: Int64?
    var maxAmountMinor: Int64?
    var dateScope: SearchDateScope = .all
    var referenceDate: Date = Date()

    var isActive: Bool {
        if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !types.isEmpty { return true }
        if accountId != nil || categoryId != nil { return true }
        if onlyReimbursable || onlyRefunds { return true }
        if minAmountMinor != nil || maxAmountMinor != nil { return true }
        return dateScope != .all
    }

    func interval(calendar: Calendar = AppCalendar.gregorian) -> DateInterval? {
        switch dateScope {
        case .all:
            return nil
        case .thisMonth:
            return AppCalendar.monthInterval(containing: referenceDate)
        case .last30Days:
            let todayStart = calendar.startOfDay(for: referenceDate)
            let start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
            let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? referenceDate
            return DateInterval(start: start, end: end)
        case .thisYear:
            let components = calendar.dateComponents([.year], from: referenceDate)
            let yearStart = calendar.date(from: components) ?? referenceDate
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? referenceDate
            return DateInterval(start: yearStart, end: yearEnd)
        }
    }

    func matches(_ txn: Txn, categoryName: String?, accountName: String?) -> Bool {
        if !types.isEmpty && !types.contains(txn.type) { return false }
        if let accountId, txn.accountId != accountId && txn.counterAccountId != accountId { return false }
        if let categoryId, txn.categoryId != categoryId { return false }
        if onlyReimbursable && !txn.isReimbursable { return false }
        if onlyRefunds && !RefundService.isRefund(txn) { return false }
        if let minAmountMinor, txn.amountMinor < minAmountMinor { return false }
        if let maxAmountMinor, txn.amountMinor > maxAmountMinor { return false }
        if let range = interval(), !range.contains(txn.occurredAt) { return false }

        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        if let note = txn.note?.lowercased(), note.contains(query) { return true }
        if let payee = txn.payee?.lowercased(), payee.contains(query) { return true }
        if let categoryName, categoryName.lowercased().contains(query) { return true }
        if let accountName, accountName.lowercased().contains(query) { return true }
        if let amount = Money.parse(query), amount == txn.amountMinor { return true }
        return false
    }
}
