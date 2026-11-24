import Foundation
import SwiftData

/// 账本（免费多账本）。所有业务数据通过 bookId 归属。
@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconEmoji: String
    var colorHex: String
    var sortOrder: Int
    var isDefault: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(name: String = "日常", iconEmoji: String = "📒", colorHex: String = "5B7C99", sortOrder: Int = 0, isDefault: Bool = true) {
        self.id = UUID()
        self.name = name
        self.iconEmoji = iconEmoji
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }
}
