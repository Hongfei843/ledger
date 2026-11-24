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
