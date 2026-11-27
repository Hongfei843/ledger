import Foundation
import SwiftData

enum ClaimStatus: String, CaseIterable, Codable {
    case draft
    case submitted
    case reimbursed
    case closed

    var displayName: String {
        switch self {
        case .draft: return "待提交"
        case .submitted: return "已提交"
        case .reimbursed: return "已到账"
        case .closed: return "已关闭"
        }
    }
}

/// 报销单。条目 = 挂在 claimId 下的 Txn，不单独建表。
@Model
final class Claim {
    @Attribute(.unique) var id: UUID
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

    init(bookId: UUID, title: String, periodMonth: String) {
        self.id = UUID()
        self.bookId = bookId
        self.title = title
        self.periodMonth = periodMonth
        self.statusRaw = ClaimStatus.draft.rawValue
        self.submittedAt = nil
        self.reimbursedAt = nil
        self.receivedAmountMinor = nil
        self.receivedAccountId = nil
        self.shortfallMinor = 0
        self.note = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var status: ClaimStatus {
        get { ClaimStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
}

/// 报销到账的唯一写入入口：到账收入与少报差额必须同事务生成，避免各页面口径漂移。
enum ReimbursementSettlementService {
    @MainActor
    @discardableResult
    static func receive(
        claim: Claim,
        totalMinor: Int64,
        amountMinor: Int64,
        accountId: UUID,
        shortfallCategoryId: UUID?,
        at date: Date = Date(),
        context: ModelContext
    ) -> Txn? {
        // 到账不得超过垫付总额，否则会凭空多出一笔收入且不再生成差额流水。
        guard amountMinor > 0, totalMinor >= 0, amountMinor <= totalMinor,
              claim.status == .draft || claim.status == .submitted else { return nil }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard accounts.contains(where: {
            $0.id == accountId && $0.bookId == claim.bookId
                && $0.deletedAt == nil && !$0.isArchived && !$0.type.isLiability
        }) else { return nil }
        if let shortfallCategoryId {
            let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
            guard categories.contains(where: {
                $0.id == shortfallCategoryId && $0.bookId == claim.bookId
                    && $0.kind == .expense && $0.deletedAt == nil && !$0.isArchived
            }) else { return nil }
        }

        let income = Txn(
            bookId: claim.bookId,
            type: .income,
            amountMinor: amountMinor,
            accountId: accountId,
            occurredAt: date,
            payee: "报销到账",
            note: claim.title
        )
        income.claimId = claim.id
        context.insert(income)

        let shortfall = max(0, totalMinor - amountMinor)
        if shortfall > 0 {
            let shortfallTxn = Txn(
                bookId: claim.bookId,
                type: .expense,
                amountMinor: shortfall,
                accountId: accountId,
                occurredAt: date,
                categoryId: shortfallCategoryId,
                payee: "报销差额",
                note: "报销差额 · \(claim.title)",
                source: .reimbursement
            )
            shortfallTxn.claimId = claim.id
            context.insert(shortfallTxn)
        }

        claim.status = .reimbursed
        claim.reimbursedAt = date
        claim.receivedAmountMinor = amountMinor
        claim.receivedAccountId = accountId
        claim.shortfallMinor = shortfall
        claim.updatedAt = date
        return income
    }

    /// 老版本只保存了 shortfallMinor，没有对应流水。按 claimId 幂等补齐，不改变到账收入。
    @MainActor
    static func backfillMissingShortfalls(context: ModelContext) {
        let claims = ((try? context.fetch(FetchDescriptor<Claim>())) ?? []).filter {
            $0.deletedAt == nil && $0.status == .reimbursed && $0.shortfallMinor > 0
        }
        guard !claims.isEmpty else { return }
        let txns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        var didChange = false

        for claim in claims {
            let related = txns.filter { $0.deletedAt == nil && $0.claimId == claim.id }
            if related.contains(where: { $0.source == .reimbursement }) { continue }
            let accountId = claim.receivedAccountId ?? related.first(where: { $0.type == .expense })?.accountId
            guard let accountId else { continue }
            let categoryId = categories.first {
                $0.bookId == claim.bookId && $0.kind == .expense && $0.name == "报销差额" && $0.deletedAt == nil
            }?.id
            let shortfall = Txn(
                bookId: claim.bookId,
                type: .expense,
                amountMinor: claim.shortfallMinor,
                accountId: accountId,
                occurredAt: claim.reimbursedAt ?? claim.updatedAt,
                categoryId: categoryId,
                payee: "报销差额",
                note: "报销差额 · \(claim.title)",
                source: .reimbursement
            )
            shortfall.claimId = claim.id
            context.insert(shortfall)
            didChange = true
        }
        if didChange { try? context.save() }
    }
}
