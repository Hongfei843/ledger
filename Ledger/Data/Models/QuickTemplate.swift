import Foundation
import SwiftData

/// 常用组合：记一笔时一键套用（类型 + 金额 + 账户 + 分类 + 商家 + 备注）。
@Model
final class QuickTemplate {
    @Attribute(.unique) var id: UUID
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

    init(
        bookId: UUID,
        name: String,
        type: TxnType,
        amountMinor: Int64? = nil,
        accountId: UUID? = nil,
        categoryId: UUID? = nil,
        payee: String? = nil,
        note: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.bookId = bookId
        self.name = name
        self.typeRaw = type.rawValue
        self.amountMinor = amountMinor
        self.accountId = accountId
        self.categoryId = categoryId
        self.payee = payee
        self.note = note
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    var type: TxnType {
        get { TxnType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
}

/// 套用模板前先过滤失效引用（账户归档/分类删除），避免记出一笔错账。
struct QuickTemplateSelection: Equatable {
    let type: TxnType
    let amountMinor: Int64?
    let accountId: UUID?
    let categoryId: UUID?
    let payee: String?
    let note: String?
}

enum QuickTemplateService {
    static func selection(
        from template: QuickTemplate,
        accounts: [Account],
        categories: [Category]
    ) -> QuickTemplateSelection? {
        guard template.deletedAt == nil else { return nil }

        let validAccountIds = Set(
            accounts
                .filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
                .map { $0.id }
        )
        let validCategoryIds = Set(
            categories
                .filter { $0.deletedAt == nil && !$0.isArchived }
                .map { $0.id }
        )

        return QuickTemplateSelection(
            type: template.type,
            amountMinor: (template.amountMinor ?? 0) > 0 ? template.amountMinor : nil,
            accountId: template.accountId.flatMap { validAccountIds.contains($0) ? $0 : nil },
            categoryId: template.categoryId.flatMap { validCategoryIds.contains($0) ? $0 : nil },
            payee: template.payee,
            note: template.note
        )
    }
}
