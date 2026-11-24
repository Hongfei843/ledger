import Foundation
import SwiftData

enum RecurrenceFrequency: String, CaseIterable, Codable {
    case daily
    case weekly
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
}

/// 周期性交易模板（房租、订阅、公积金缴存等）。
@Model
final class RecurringRule {
    @Attribute(.unique) var id: UUID
    var bookId: UUID
    var title: String
    var templateTypeRaw: String
    var amountMinor: Int64
    var accountId: UUID
    var counterAccountId: UUID?
    var categoryId: UUID?
    var note: String?
    var frequencyRaw: String
    var interval: Int
    var startDate: Date
    var nextDate: Date
    var autoCreate: Bool
    var isPaused: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        bookId: UUID,
        title: String,
        templateType: TxnType,
        amountMinor: Int64,
        accountId: UUID,
        frequency: RecurrenceFrequency,
        startDate: Date
    ) {
        self.id = UUID()
        self.bookId = bookId
        self.title = title
        self.templateTypeRaw = templateType.rawValue
        self.amountMinor = amountMinor
        self.accountId = accountId
        self.counterAccountId = nil
        self.categoryId = nil
        self.note = nil
        self.frequencyRaw = frequency.rawValue
        self.interval = 1
        self.startDate = startDate
        self.nextDate = startDate
        self.autoCreate = false
        self.isPaused = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var templateType: TxnType {
        get { TxnType(rawValue: templateTypeRaw) ?? .expense }
        set { templateTypeRaw = newValue.rawValue }
    }
}
