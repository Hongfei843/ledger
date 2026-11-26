// 由 scripts/gen-backup-dtos.py 自动生成，勿手改。
// 修改模型字段后，重新运行脚本生成。
import Foundation

struct BookDTO: Codable {
    var id: UUID
    var name: String
    var iconEmoji: String
    var colorHex: String
    var sortOrder: Int
    var isDefault: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

extension BookDTO {
    init(_ model: Book) {
        self.id = model.id
        self.name = model.name
        self.iconEmoji = model.iconEmoji
        self.colorHex = model.colorHex
        self.sortOrder = model.sortOrder
        self.isDefault = model.isDefault
        self.isArchived = model.isArchived
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: Book) {
        model.id = id
        model.name = name
        model.iconEmoji = iconEmoji
        model.colorHex = colorHex
        model.sortOrder = sortOrder
        model.isDefault = isDefault
        model.isArchived = isArchived
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct AccountDTO: Codable {
    var id: UUID
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
    var bankId: String?
    var cardTail: String?
    var lastReconciledAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

extension AccountDTO {
    init(_ model: Account) {
        self.id = model.id
        self.bookId = model.bookId
        self.name = model.name
        self.typeRaw = model.typeRaw
        self.institution = model.institution
        self.currencyCode = model.currencyCode
        self.openingBalanceMinor = model.openingBalanceMinor
        self.cachedBalanceMinor = model.cachedBalanceMinor
        self.creditLimitMinor = model.creditLimitMinor
        self.billDay = model.billDay
        self.dueDay = model.dueDay
        self.contributionMonthlyMinor = model.contributionMonthlyMinor
        self.isRestricted = model.isRestricted
        self.isSystem = model.isSystem
        self.linkedLoanId = model.linkedLoanId
        self.iconEmoji = model.iconEmoji
        self.colorHex = model.colorHex
        self.sortOrder = model.sortOrder
        self.includeInNetWorth = model.includeInNetWorth
        self.isArchived = model.isArchived
        self.bankId = model.bankId
        self.cardTail = model.cardTail
        self.lastReconciledAt = model.lastReconciledAt
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: Account) {
        model.id = id
        model.bookId = bookId
        model.name = name
        model.typeRaw = typeRaw
        model.institution = institution
        model.currencyCode = currencyCode
        model.openingBalanceMinor = openingBalanceMinor
        model.cachedBalanceMinor = cachedBalanceMinor
        model.creditLimitMinor = creditLimitMinor
        model.billDay = billDay
        model.dueDay = dueDay
        model.contributionMonthlyMinor = contributionMonthlyMinor
        model.isRestricted = isRestricted
        model.isSystem = isSystem
        model.linkedLoanId = linkedLoanId
        model.iconEmoji = iconEmoji
        model.colorHex = colorHex
        model.sortOrder = sortOrder
        model.includeInNetWorth = includeInNetWorth
        model.isArchived = isArchived
        model.bankId = bankId
        model.cardTail = cardTail
        model.lastReconciledAt = lastReconciledAt
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct CategoryDTO: Codable {
    var id: UUID
    var bookId: UUID
    var name: String
    var kindRaw: String
    var parentId: UUID?
    var iconEmoji: String
    var colorHex: String
    var sortOrder: Int
    var defaultReimbursable: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

extension CategoryDTO {
    init(_ model: Category) {
        self.id = model.id
        self.bookId = model.bookId
        self.name = model.name
        self.kindRaw = model.kindRaw
        self.parentId = model.parentId
        self.iconEmoji = model.iconEmoji
        self.colorHex = model.colorHex
        self.sortOrder = model.sortOrder
        self.defaultReimbursable = model.defaultReimbursable
        self.isArchived = model.isArchived
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: Category) {
        model.id = id
        model.bookId = bookId
        model.name = name
        model.kindRaw = kindRaw
        model.parentId = parentId
        model.iconEmoji = iconEmoji
        model.colorHex = colorHex
        model.sortOrder = sortOrder
        model.defaultReimbursable = defaultReimbursable
        model.isArchived = isArchived
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct TxnDTO: Codable {
    var id: UUID
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
}

extension TxnDTO {
    init(_ model: Txn) {
        self.id = model.id
        self.bookId = model.bookId
        self.typeRaw = model.typeRaw
        self.amountMinor = model.amountMinor
        self.accountId = model.accountId
        self.counterAccountId = model.counterAccountId
        self.categoryId = model.categoryId
        self.occurredAt = model.occurredAt
        self.payee = model.payee
        self.note = model.note
        self.isReimbursable = model.isReimbursable
        self.claimId = model.claimId
        self.refundOfTxnId = model.refundOfTxnId
        self.loanId = model.loanId
        self.loanScheduleItemId = model.loanScheduleItemId
        self.principalMinor = model.principalMinor
        self.interestMinor = model.interestMinor
        self.sourceRaw = model.sourceRaw
        self.externalId = model.externalId
        self.captureId = model.captureId
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: Txn) {
        model.id = id
        model.bookId = bookId
        model.typeRaw = typeRaw
        model.amountMinor = amountMinor
        model.accountId = accountId
        model.counterAccountId = counterAccountId
        model.categoryId = categoryId
        model.occurredAt = occurredAt
        model.payee = payee
        model.note = note
        model.isReimbursable = isReimbursable
        model.claimId = claimId
        model.refundOfTxnId = refundOfTxnId
        model.loanId = loanId
        model.loanScheduleItemId = loanScheduleItemId
        model.principalMinor = principalMinor
        model.interestMinor = interestMinor
        model.sourceRaw = sourceRaw
        model.externalId = externalId
        model.captureId = captureId
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct ClaimDTO: Codable {
    var id: UUID
    var bookId: UUID
    var title: String
    var periodMonth: String
    var statusRaw: String
    var submittedAt: Date?
    var reimbursedAt: Date?
    var receivedAmountMinor: Int64?
    var receivedAccountId: UUID?
    var shortfallMinor: Int64
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

extension ClaimDTO {
    init(_ model: Claim) {
        self.id = model.id
        self.bookId = model.bookId
        self.title = model.title
        self.periodMonth = model.periodMonth
        self.statusRaw = model.statusRaw
        self.submittedAt = model.submittedAt
        self.reimbursedAt = model.reimbursedAt
        self.receivedAmountMinor = model.receivedAmountMinor
        self.receivedAccountId = model.receivedAccountId
        self.shortfallMinor = model.shortfallMinor
        self.note = model.note
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: Claim) {
        model.id = id
        model.bookId = bookId
        model.title = title
        model.periodMonth = periodMonth
        model.statusRaw = statusRaw
        model.submittedAt = submittedAt
        model.reimbursedAt = reimbursedAt
        model.receivedAmountMinor = receivedAmountMinor
        model.receivedAccountId = receivedAccountId
        model.shortfallMinor = shortfallMinor
        model.note = note
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct LoanDTO: Codable {
    var id: UUID
    var bookId: UUID
    var name: String
    var typeRaw: String
    var lender: String?
    var principalMinor: Int64
    var outstandingPrincipalMinor: Int64
    var annualRateBp: Int
    var termMonths: Int
    var startDate: Date
    var firstDueDate: Date
    var dueDay: Int
    var repaymentMethodRaw: String
    var paymentAccountId: UUID
    var providentAccountId: UUID?
    var providentModeRaw: String
    var fundingSourceRaw: String
    var statusRaw: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

extension LoanDTO {
    init(_ model: Loan) {
        self.id = model.id
        self.bookId = model.bookId
        self.name = model.name
        self.typeRaw = model.typeRaw
        self.lender = model.lender
        self.principalMinor = model.principalMinor
        self.outstandingPrincipalMinor = model.outstandingPrincipalMinor
        self.annualRateBp = model.annualRateBp
        self.termMonths = model.termMonths
        self.startDate = model.startDate
        self.firstDueDate = model.firstDueDate
        self.dueDay = model.dueDay
        self.repaymentMethodRaw = model.repaymentMethodRaw
        self.paymentAccountId = model.paymentAccountId
        self.providentAccountId = model.providentAccountId
        self.providentModeRaw = model.providentModeRaw
        self.fundingSourceRaw = model.fundingSourceRaw
        self.statusRaw = model.statusRaw
        self.note = model.note
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: Loan) {
        model.id = id
        model.bookId = bookId
        model.name = name
        model.typeRaw = typeRaw
        model.lender = lender
        model.principalMinor = principalMinor
        model.outstandingPrincipalMinor = outstandingPrincipalMinor
        model.annualRateBp = annualRateBp
        model.termMonths = termMonths
        model.startDate = startDate
        model.firstDueDate = firstDueDate
        model.dueDay = dueDay
        model.repaymentMethodRaw = repaymentMethodRaw
        model.paymentAccountId = paymentAccountId
        model.providentAccountId = providentAccountId
        model.providentModeRaw = providentModeRaw
        model.fundingSourceRaw = fundingSourceRaw
        model.statusRaw = statusRaw
        model.note = note
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct LoanScheduleItemDTO: Codable {
    var id: UUID
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
}

extension LoanScheduleItemDTO {
    init(_ model: LoanScheduleItem) {
        self.id = model.id
        self.loanId = model.loanId
        self.periodIndex = model.periodIndex
        self.dueDate = model.dueDate
        self.principalMinor = model.principalMinor
        self.interestMinor = model.interestMinor
        self.feeMinor = model.feeMinor
        self.isPaid = model.isPaid
        self.paidAt = model.paidAt
        self.paidAmountMinor = model.paidAmountMinor
        self.fundingSourceRaw = model.fundingSourceRaw
        self.cashPaidMinor = model.cashPaidMinor
        self.providentPaidMinor = model.providentPaidMinor
        self.paymentTxnId = model.paymentTxnId
        self.interestTxnId = model.interestTxnId
        self.isAdjusted = model.isAdjusted
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: LoanScheduleItem) {
        model.id = id
        model.loanId = loanId
        model.periodIndex = periodIndex
        model.dueDate = dueDate
        model.principalMinor = principalMinor
        model.interestMinor = interestMinor
        model.feeMinor = feeMinor
        model.isPaid = isPaid
        model.paidAt = paidAt
        model.paidAmountMinor = paidAmountMinor
        model.fundingSourceRaw = fundingSourceRaw
        model.cashPaidMinor = cashPaidMinor
        model.providentPaidMinor = providentPaidMinor
        model.paymentTxnId = paymentTxnId
        model.interestTxnId = interestTxnId
        model.isAdjusted = isAdjusted
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct StatementDTO: Codable {
    var id: UUID
    var accountId: UUID
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
}

extension StatementDTO {
    init(_ model: Statement) {
        self.id = model.id
        self.accountId = model.accountId
        self.periodMonth = model.periodMonth
        self.billAmountMinor = model.billAmountMinor
        self.minimumPaymentMinor = model.minimumPaymentMinor
        self.paidAmountMinor = model.paidAmountMinor
        self.dueDate = model.dueDate
        self.paidAt = model.paidAt
        self.statusRaw = model.statusRaw
        self.note = model.note
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: Statement) {
        model.id = id
        model.accountId = accountId
        model.periodMonth = periodMonth
        model.billAmountMinor = billAmountMinor
        model.minimumPaymentMinor = minimumPaymentMinor
        model.paidAmountMinor = paidAmountMinor
        model.dueDate = dueDate
        model.paidAt = paidAt
        model.statusRaw = statusRaw
        model.note = note
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct ReconciliationRunDTO: Codable {
    var id: UUID
    var bookId: UUID
    var createdAt: Date
    var accountCount: Int
    var diffCount: Int
    var totalDiffMinor: Int64
}

extension ReconciliationRunDTO {
    init(_ model: ReconciliationRun) {
        self.id = model.id
        self.bookId = model.bookId
        self.createdAt = model.createdAt
        self.accountCount = model.accountCount
        self.diffCount = model.diffCount
        self.totalDiffMinor = model.totalDiffMinor
    }

    func apply(to model: ReconciliationRun) {
        model.id = id
        model.bookId = bookId
        model.createdAt = createdAt
        model.accountCount = accountCount
        model.diffCount = diffCount
        model.totalDiffMinor = totalDiffMinor
    }
}

struct DebtDTO: Codable {
    var id: UUID
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
}

extension DebtDTO {
    init(_ model: Debt) {
        self.id = model.id
        self.bookId = model.bookId
        self.directionRaw = model.directionRaw
        self.counterparty = model.counterparty
        self.amountMinor = model.amountMinor
        self.occurredAt = model.occurredAt
        self.dueDate = model.dueDate
        self.note = model.note
        self.isSettled = model.isSettled
        self.settledAt = model.settledAt
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: Debt) {
        model.id = id
        model.bookId = bookId
        model.directionRaw = directionRaw
        model.counterparty = counterparty
        model.amountMinor = amountMinor
        model.occurredAt = occurredAt
        model.dueDate = dueDate
        model.note = note
        model.isSettled = isSettled
        model.settledAt = settledAt
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct MerchantRuleDTO: Codable {
    var id: UUID
    var payeeKey: String
    var categoryId: UUID
    var hitCount: Int
    var lastUsedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

extension MerchantRuleDTO {
    init(_ model: MerchantRule) {
        self.id = model.id
        self.payeeKey = model.payeeKey
        self.categoryId = model.categoryId
        self.hitCount = model.hitCount
        self.lastUsedAt = model.lastUsedAt
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: MerchantRule) {
        model.id = id
        model.payeeKey = payeeKey
        model.categoryId = categoryId
        model.hitCount = hitCount
        model.lastUsedAt = lastUsedAt
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct CaptureRecordDTO: Codable {
    var id: UUID
    var imagePath: String?
    var ocrText: String
    var parsedAmountMinor: Int64?
    var parsedPayee: String?
    var parsedAccountId: UUID?
    var parsedCategoryId: UUID?
    var confidence: Double
    var isAccepted: Bool
    var sourceType: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

extension CaptureRecordDTO {
    init(_ model: CaptureRecord) {
        self.id = model.id
        self.imagePath = model.imagePath
        self.ocrText = model.ocrText
        self.parsedAmountMinor = model.parsedAmountMinor
        self.parsedPayee = model.parsedPayee
        self.parsedAccountId = model.parsedAccountId
        self.parsedCategoryId = model.parsedCategoryId
        self.confidence = model.confidence
        self.isAccepted = model.isAccepted
        self.sourceType = model.sourceType
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: CaptureRecord) {
        model.id = id
        model.imagePath = imagePath
        model.ocrText = ocrText
        model.parsedAmountMinor = parsedAmountMinor
        model.parsedPayee = parsedPayee
        model.parsedAccountId = parsedAccountId
        model.parsedCategoryId = parsedCategoryId
        model.confidence = confidence
        model.isAccepted = isAccepted
        model.sourceType = sourceType
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct RecurringRuleDTO: Codable {
    var id: UUID
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
}

extension RecurringRuleDTO {
    init(_ model: RecurringRule) {
        self.id = model.id
        self.bookId = model.bookId
        self.title = model.title
        self.templateTypeRaw = model.templateTypeRaw
        self.amountMinor = model.amountMinor
        self.accountId = model.accountId
        self.counterAccountId = model.counterAccountId
        self.categoryId = model.categoryId
        self.note = model.note
        self.frequencyRaw = model.frequencyRaw
        self.interval = model.interval
        self.startDate = model.startDate
        self.nextDate = model.nextDate
        self.autoCreate = model.autoCreate
        self.isPaused = model.isPaused
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: RecurringRule) {
        model.id = id
        model.bookId = bookId
        model.title = title
        model.templateTypeRaw = templateTypeRaw
        model.amountMinor = amountMinor
        model.accountId = accountId
        model.counterAccountId = counterAccountId
        model.categoryId = categoryId
        model.note = note
        model.frequencyRaw = frequencyRaw
        model.interval = interval
        model.startDate = startDate
        model.nextDate = nextDate
        model.autoCreate = autoCreate
        model.isPaused = isPaused
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}

struct QuickTemplateDTO: Codable {
    var id: UUID
    var bookId: UUID
    var name: String
    var typeRaw: String
    var amountMinor: Int64?
    var accountId: UUID?
    var categoryId: UUID?
    var payee: String?
    var note: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

extension QuickTemplateDTO {
    init(_ model: QuickTemplate) {
        self.id = model.id
        self.bookId = model.bookId
        self.name = model.name
        self.typeRaw = model.typeRaw
        self.amountMinor = model.amountMinor
        self.accountId = model.accountId
        self.categoryId = model.categoryId
        self.payee = model.payee
        self.note = model.note
        self.sortOrder = model.sortOrder
        self.createdAt = model.createdAt
        self.updatedAt = model.updatedAt
        self.deletedAt = model.deletedAt
    }

    func apply(to model: QuickTemplate) {
        model.id = id
        model.bookId = bookId
        model.name = name
        model.typeRaw = typeRaw
        model.amountMinor = amountMinor
        model.accountId = accountId
        model.categoryId = categoryId
        model.payee = payee
        model.note = note
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.deletedAt = deletedAt
    }
}
