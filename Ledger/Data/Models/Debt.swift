import Foundation
import SwiftData

enum DebtDirection: String, CaseIterable, Codable {
    /// 我借给别人（应收）
    case lend
    /// 我向别人借（应付）
    case borrow

    var displayName: String {
        switch self {
        case .lend: return "借出"
        case .borrow: return "借入"
        }
    }
}

/// 借入借出。只做跟踪，不自动生成流水，避免和「人情」类支出重复计账。
@Model
final class Debt {
    @Attribute(.unique) var id: UUID
    var bookId: UUID
    var directionRaw: String
    var counterparty: String
    var amountMinor: Int64
    var occurredAt: Date
    var dueDate: Date?
    var note: String?
    var isSettled: Bool
    var settledAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(bookId: UUID, direction: DebtDirection, counterparty: String, amountMinor: Int64, occurredAt: Date = Date(), dueDate: Date? = nil) {
        self.id = UUID()
        self.bookId = bookId
        self.directionRaw = direction.rawValue
        self.counterparty = counterparty
        self.amountMinor = amountMinor
        self.occurredAt = occurredAt
        self.dueDate = dueDate
        self.note = nil
        self.isSettled = false
        self.settledAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var direction: DebtDirection {
        get { DebtDirection(rawValue: directionRaw) ?? .lend }
        set { directionRaw = newValue.rawValue }
    }

    /// 逾期未结清
    func isOverdue(reference: Date = Date(), calendar: Calendar = AppCalendar.gregorian) -> Bool {
        guard !isSettled, let dueDate else { return false }
        return calendar.startOfDay(for: reference) > calendar.startOfDay(for: dueDate)
    }
}

enum DebtService {
    /// 未结清的应收 / 应付合计
    static func summary(_ debts: [Debt]) -> (receivable: Int64, payable: Int64) {
        var receivable: Int64 = 0
        var payable: Int64 = 0
        for debt in debts where debt.deletedAt == nil && !debt.isSettled {
            switch debt.direction {
            case .lend: receivable += debt.amountMinor
            case .borrow: payable += debt.amountMinor
            }
        }
        return (receivable, payable)
    }
}
