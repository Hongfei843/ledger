import Foundation
import SwiftData

enum LoanType: String, CaseIterable, Codable {
    case mortgageCommercial
    case mortgageProvident
    case mortgageCombined
    case consumerInstallment
    case carLoan
    case creditCardInstallment
    case other

    var displayName: String {
        switch self {
        case .mortgageCommercial: return "商业房贷"
        case .mortgageProvident: return "公积金贷"
        case .mortgageCombined: return "组合贷"
        case .consumerInstallment: return "小额现金分期"
        case .carLoan: return "车贷"
        case .creditCardInstallment: return "信用卡分期"
        case .other: return "其他"
        }
    }
}

enum RepaymentMethod: String, CaseIterable, Codable {
    case equalInstallment
    case equalPrincipal
    case interestOnly
    case bullet
    case installmentFee

    var displayName: String {
        switch self {
        case .equalInstallment: return "等额本息"
        case .equalPrincipal: return "等额本金"
        case .interestOnly: return "先息后本"
        case .bullet: return "到期一次还本付息"
        case .installmentFee: return "分期手续费"
        }
    }
}

enum ProvidentMode: String, CaseIterable, Codable {
    case none
    case monthlyOffset
    case annualOffset
    case mixed

    var displayName: String {
        switch self {
        case .none: return "不冲还"
        case .monthlyOffset: return "按月冲还"
        case .annualOffset: return "按年冲还"
        case .mixed: return "混合"
        }
    }
}

enum FundingSource: String, CaseIterable, Codable {
    case cash
    case providentFund
    case mixed
}

enum LoanStatus: String, CaseIterable, Codable {
    case active
    case paidOff
    case archived
}

@Model
final class Loan {
    @Attribute(.unique) var id: UUID
    var bookId: UUID
    var name: String
    var typeRaw: String
    var lender: String?
    var principalMinor: Int64
    var outstandingPrincipalMinor: Int64
    /// 年利率，单位基点(bp)：4.2% = 420
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

    init(
        bookId: UUID,
        name: String,
        type: LoanType,
        principalMinor: Int64,
        annualRateBp: Int,
        termMonths: Int,
        startDate: Date,
        firstDueDate: Date,
        dueDay: Int,
        repaymentMethod: RepaymentMethod,
        paymentAccountId: UUID
    ) {
        self.id = UUID()
        self.bookId = bookId
        self.name = name
        self.typeRaw = type.rawValue
        self.lender = nil
        self.principalMinor = principalMinor
        self.outstandingPrincipalMinor = principalMinor
        self.annualRateBp = annualRateBp
        self.termMonths = termMonths
        self.startDate = startDate
        self.firstDueDate = firstDueDate
        self.dueDay = dueDay
        self.repaymentMethodRaw = repaymentMethod.rawValue
        self.paymentAccountId = paymentAccountId
        self.providentAccountId = nil
        self.providentModeRaw = ProvidentMode.none.rawValue
        self.fundingSourceRaw = FundingSource.cash.rawValue
        self.statusRaw = LoanStatus.active.rawValue
        self.note = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var type: LoanType {
        get { LoanType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var repaymentMethod: RepaymentMethod {
        get { RepaymentMethod(rawValue: repaymentMethodRaw) ?? .equalInstallment }
        set { repaymentMethodRaw = newValue.rawValue }
    }

    var providentMode: ProvidentMode {
        get { ProvidentMode(rawValue: providentModeRaw) ?? .none }
        set { providentModeRaw = newValue.rawValue }
    }

    var fundingSource: FundingSource {
        get { FundingSource(rawValue: fundingSourceRaw) ?? .cash }
        set { fundingSourceRaw = newValue.rawValue }
    }

    var status: LoanStatus {
        get { LoanStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var annualRatePercent: Double {
        Double(annualRateBp) / 100.0
    }
}
