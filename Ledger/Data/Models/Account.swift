import Foundation
import SwiftData

enum AccountType: String, CaseIterable, Identifiable, Codable {
    case cash
    case debit
    case credit
    case ewallet
    case bnpl
    case prepaid
    case providentFund
    case loan
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: return "现金"
        case .debit: return "储蓄卡"
        case .credit: return "信用卡"
        case .ewallet: return "电子钱包"
        case .bnpl: return "信用付"
        case .prepaid: return "储值卡"
        case .providentFund: return "公积金"
        case .loan: return "贷款"
        case .other: return "其他"
        }
    }

    var isLiability: Bool {
        self == .credit || self == .bnpl || self == .loan
    }

    var isCreditLike: Bool {
        self == .credit || self == .bnpl
    }
}

/// 账户。余额符号约定：资产为正、负债为负。
@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var bookId: UUID
    var name: String
    var typeRaw: String
    var institution: String?
    var currencyCode: String
    var openingBalanceMinor: Int64
    var cachedBalanceMinor: Int64
    var creditLimitMinor: Int64?
    var billDay: Int?
    var dueDay: Int?
    var contributionMonthlyMinor: Int64?
    var isRestricted: Bool
    var isSystem: Bool
    var linkedLoanId: UUID?
    var iconEmoji: String
    var colorHex: String
    var sortOrder: Int
    var includeInNetWorth: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        bookId: UUID,
        name: String,
        type: AccountType,
        openingBalanceMinor: Int64 = 0,
        iconEmoji: String = "💳",
        colorHex: String = "5B7C99",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.bookId = bookId
        self.name = name
        self.typeRaw = type.rawValue
        self.institution = nil
        self.currencyCode = "CNY"
        self.openingBalanceMinor = openingBalanceMinor
        self.cachedBalanceMinor = openingBalanceMinor
        self.creditLimitMinor = nil
        self.billDay = nil
        self.dueDay = nil
        self.contributionMonthlyMinor = nil
        self.isRestricted = type == .providentFund
        self.isSystem = type == .loan
        self.linkedLoanId = nil
        self.iconEmoji = iconEmoji
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.includeInNetWorth = true
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// 信用卡欠款（正数表示欠多少）
    var debtMinor: Int64 {
        cachedBalanceMinor < 0 ? -cachedBalanceMinor : 0
    }

    /// 信用卡可用额度
    var availableCreditMinor: Int64? {
        guard let limit = creditLimitMinor else { return nil }
        return limit + cachedBalanceMinor
    }
}
