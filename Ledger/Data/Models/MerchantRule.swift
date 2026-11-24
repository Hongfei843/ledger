import Foundation
import SwiftData

/// 商户 → 分类 的学习表，用于 OCR 自动归类。
@Model
final class MerchantRule {
    @Attribute(.unique) var id: UUID
    var payeeKey: String
    var categoryId: UUID
    var hitCount: Int
    var lastUsedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(payeeKey: String, categoryId: UUID) {
        self.id = UUID()
        self.payeeKey = payeeKey
        self.categoryId = categoryId
        self.hitCount = 1
        self.lastUsedAt = Date()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }
}
