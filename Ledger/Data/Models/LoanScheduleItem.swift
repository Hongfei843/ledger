import Foundation
import SwiftData

/// 还款计划的一期。
@Model
final class LoanScheduleItem {
    @Attribute(.unique) var id: UUID
    var loanId: UUID
    var periodIndex: Int
    var dueDate: Date
    var principalMinor: Int64
    var interestMinor: Int64
    var feeMinor: Int64
    var isPaid: Bool
    var paidAt: Date?
    var paidAmountMinor: Int64?
    var fundingSourceRaw: String
    var cashPaidMinor: Int64
    var providentPaidMinor: Int64
    var paymentTxnId: UUID?
    var interestTxnId: UUID?
    var isAdjusted: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(loanId: UUID, periodIndex: Int, dueDate: Date, principalMinor: Int64, interestMinor: Int64, feeMinor: Int64) {
        self.id = UUID()
        self.loanId = loanId
        self.periodIndex = periodIndex
        self.dueDate = dueDate
        self.principalMinor = principalMinor
        self.interestMinor = interestMinor
        self.feeMinor = feeMinor
        self.isPaid = false
        self.paidAt = nil
        self.paidAmountMinor = nil
        self.fundingSourceRaw = FundingSource.cash.rawValue
        self.cashPaidMinor = 0
        self.providentPaidMinor = 0
        self.paymentTxnId = nil
        self.interestTxnId = nil
        self.isAdjusted = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var totalMinor: Int64 {
        principalMinor + interestMinor + feeMinor
    }

    var fundingSource: FundingSource {
        get { FundingSource(rawValue: fundingSourceRaw) ?? .cash }
        set { fundingSourceRaw = newValue.rawValue }
    }
}
