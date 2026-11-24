import Foundation
import SwiftData

enum CategoryKind: String, CaseIterable, Codable {
    case expense
    case income
}

@Model
final class Category {
    @Attribute(.unique) var id: UUID
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

    init(
        bookId: UUID,
        name: String,
        kind: CategoryKind,
        parentId: UUID? = nil,
        iconEmoji: String = "🍽️",
        colorHex: String = "5B7C99",
        sortOrder: Int = 0,
        defaultReimbursable: Bool = false
    ) {
        self.id = UUID()
        self.bookId = bookId
        self.name = name
        self.kindRaw = kind.rawValue
        self.parentId = parentId
        self.iconEmoji = iconEmoji
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.defaultReimbursable = defaultReimbursable
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
}
