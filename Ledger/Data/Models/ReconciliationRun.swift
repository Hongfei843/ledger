import Foundation
import SwiftData

/// 一次对账的记录。用于回答「上次对账是什么时候、差异有多大」。
@Model
final class ReconciliationRun {
    @Attribute(.unique) var id: UUID
    var bookId: UUID
    var createdAt: Date
    /// 参与对账的账户数
    var accountCount: Int
    /// 有差异的账户数
    var diffCount: Int
    /// 差异绝对值合计
    var totalDiffMinor: Int64

    init(bookId: UUID, accountCount: Int, diffCount: Int, totalDiffMinor: Int64) {
        self.id = UUID()
        self.bookId = bookId
        self.createdAt = Date()
        self.accountCount = accountCount
        self.diffCount = diffCount
        self.totalDiffMinor = totalDiffMinor
    }
}
