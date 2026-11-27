import Foundation
import SwiftData

enum TxnType: String, CaseIterable, Codable {
    case expense
    case income
    case transfer
    case adjustment
    case loanPayment

    var displayName: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        case .transfer: return "转账"
        case .adjustment: return "余额调整"
        case .loanPayment: return "还款"
        }
    }

    /// 是否计入收入/支出统计
    var countsAsCashFlow: Bool {
        self == .expense || self == .income
    }
}

enum TxnSource: String, Codable {
    case manual
    case imported
    case recurring
    case ocr
    case sync
    case reimbursement
}

/// 流水。money 一律 Int64 分，金额恒为正，方向由 type 决定。
@Model
final class Txn {
    @Attribute(.unique) var id: UUID
    var bookId: UUID
    var typeRaw: String
    var amountMinor: Int64
    var accountId: UUID
    var counterAccountId: UUID?
    var categoryId: UUID?
    var occurredAt: Date
    var payee: String?
    var note: String?
    var isReimbursable: Bool
    var claimId: UUID?
    /// 退款对应的原支出流水 id（退款流水本身是 income）
    var refundOfTxnId: UUID?
    var loanId: UUID?
    var loanScheduleItemId: UUID?
    var principalMinor: Int64?
    var interestMinor: Int64?
    var sourceRaw: String
    var externalId: String?
    var captureId: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        bookId: UUID,
        type: TxnType,
        amountMinor: Int64,
        accountId: UUID,
        occurredAt: Date = Date(),
        categoryId: UUID? = nil,
        counterAccountId: UUID? = nil,
        payee: String? = nil,
        note: String? = nil,
        source: TxnSource = .manual
    ) {
        self.id = UUID()
        self.bookId = bookId
        self.typeRaw = type.rawValue
        self.amountMinor = amountMinor
        self.accountId = accountId
        self.counterAccountId = counterAccountId
        self.categoryId = categoryId
        self.occurredAt = occurredAt
        self.payee = payee
        self.note = note
        self.isReimbursable = false
        self.claimId = nil
        self.refundOfTxnId = nil
        self.loanId = nil
        self.loanScheduleItemId = nil
        self.principalMinor = nil
        self.interestMinor = nil
        self.sourceRaw = source.rawValue
        self.externalId = nil
        self.captureId = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var type: TxnType {
        get { TxnType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var source: TxnSource {
        get { TxnSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var isDeleted: Bool { deletedAt != nil }

    /// 通用流水编辑器只支持三种基础类型；贷款关联流水必须由贷款模块维护。
    var canEditInEntrySheet: Bool {
        loanId == nil && (type == .expense || type == .income || type == .transfer)
    }

    /// 直接删除贷款还款流水会让还款计划与账户余额失去一致性。
    var canDeleteFromTransactionList: Bool { loanId == nil }

    /// 是否是某笔支出的退款（统计里作为支出冲减，不算收入）
    var isRefund: Bool { type == .income && refundOfTxnId != nil }

    /// 对账户余额的增量（资产正、负债负）
    var balanceDelta: Int64 {
        switch type {
        case .expense:
            return -amountMinor
        case .income:
            return amountMinor
        case .transfer:
            return -amountMinor
        case .adjustment:
            return amountMinor
        case .loanPayment:
            return 0
        }
    }
}
