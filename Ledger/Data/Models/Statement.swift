import Foundation
import SwiftData

enum StatementStatus: String, CaseIterable, Codable {
    case pending    // 未出账
    case issued     // 已出账
    case partial    // 部分还款
    case paid       // 已还清
    case overdue    // 逾期

    var displayName: String {
        switch self {
        case .pending: return "未出账"
        case .issued: return "已出账"
        case .partial: return "部分还款"
        case .paid: return "已还清"
        case .overdue: return "逾期"
        }
    }
}

/// 信用卡 / 信用付的账单。
/// 记录银行给的「真实出账金额」，与 App 计算的金额比对，差异才有意义。
@Model
final class Statement {
    @Attribute(.unique) var id: UUID
    var accountId: UUID
    /// 归属月份 "yyyy-MM"
    var periodMonth: String
    var billAmountMinor: Int64
    var minimumPaymentMinor: Int64
    var paidAmountMinor: Int64
    var dueDate: Date
    var paidAt: Date?
    var statusRaw: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(accountId: UUID, periodMonth: String, billAmountMinor: Int64, minimumPaymentMinor: Int64, dueDate: Date) {
        self.id = UUID()
        self.accountId = accountId
        self.periodMonth = periodMonth
        self.billAmountMinor = billAmountMinor
        self.minimumPaymentMinor = minimumPaymentMinor
        self.paidAmountMinor = 0
        self.dueDate = dueDate
        self.paidAt = nil
        self.statusRaw = StatementStatus.issued.rawValue
        self.note = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var status: StatementStatus {
        get { StatementStatus(rawValue: statusRaw) ?? .issued }
        set { statusRaw = newValue.rawValue }
    }

    /// 还欠多少
    var outstandingMinor: Int64 {
        max(0, billAmountMinor - paidAmountMinor)
    }

    var isSettled: Bool {
        paidAmountMinor >= billAmountMinor
    }

    /// 依据已还金额与到期日推导状态
    func refreshStatus(reference: Date = Date(), calendar: Calendar = AppCalendar.gregorian) {
        if isSettled {
            status = .paid
            if paidAt == nil { paidAt = Date() }
        } else if paidAmountMinor > 0 {
            status = .partial
        } else if calendar.startOfDay(for: reference) > calendar.startOfDay(for: dueDate) {
            status = .overdue
        } else {
            status = .issued
        }
        updatedAt = Date()
    }
}
