import Foundation
import SwiftData

/// 首次启动的初始化数据：默认账本 + 内置分类 + 两个占位账户。
enum SeedData {
    struct CategorySeed {
        let name: String
        let emoji: String
    }

    static let expenseCategories: [CategorySeed] = [
        CategorySeed(name: "餐饮", emoji: "🍜"),
        CategorySeed(name: "买菜", emoji: "🥬"),
        CategorySeed(name: "交通", emoji: "🚇"),
        CategorySeed(name: "购物", emoji: "🛍️"),
        CategorySeed(name: "日用", emoji: "🧻"),
        CategorySeed(name: "居住", emoji: "🏠"),
        CategorySeed(name: "通讯", emoji: "📱"),
        CategorySeed(name: "娱乐", emoji: "🎮"),
        CategorySeed(name: "医疗", emoji: "💊"),
        CategorySeed(name: "教育", emoji: "📚"),
        CategorySeed(name: "人情送礼", emoji: "🎁"),
        CategorySeed(name: "旅行", emoji: "✈️"),
        CategorySeed(name: "宠物", emoji: "🐱"),
        CategorySeed(name: "订阅服务", emoji: "🔔"),
        CategorySeed(name: "利息支出", emoji: "🏦"),
        CategorySeed(name: "手续费", emoji: "🧾"),
        CategorySeed(name: "报销差额", emoji: "📎"),
        CategorySeed(name: "其他", emoji: "📦")
    ]

    static let incomeCategories: [CategorySeed] = [
        CategorySeed(name: "工资", emoji: "💰"),
        CategorySeed(name: "奖金", emoji: "🏆"),
        CategorySeed(name: "兼职", emoji: "💼"),
        CategorySeed(name: "报销收入", emoji: "🧾"),
        CategorySeed(name: "投资收益", emoji: "📈"),
        CategorySeed(name: "红包", emoji: "🧧"),
        CategorySeed(name: "退款", emoji: "↩️"),
        CategorySeed(name: "其他", emoji: "📦")
    ]

    /// 幂等：只在没有任何账本时执行。
    static func bootstrapIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Book>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let book = Book()
        context.insert(book)

        for (index, seed) in expenseCategories.enumerated() {
            let category = Category(
                bookId: book.id,
                name: seed.name,
                kind: .expense,
                iconEmoji: seed.emoji,
                sortOrder: index,
                defaultReimbursable: seed.name == "交通" || seed.name == "旅行"
            )
            context.insert(category)
        }

        for (index, seed) in incomeCategories.enumerated() {
            let category = Category(
                bookId: book.id,
                name: seed.name,
                kind: .income,
                iconEmoji: seed.emoji,
                sortOrder: index
            )
            context.insert(category)
        }

        let cash = Account(bookId: book.id, name: "现金", type: .cash, iconEmoji: "💵", sortOrder: 0)
        let debit = Account(bookId: book.id, name: "储蓄卡", type: .debit, iconEmoji: "🏦", sortOrder: 1)
        let credit = Account(bookId: book.id, name: "信用卡", type: .credit, iconEmoji: "💳", colorHex: "C98A9B", sortOrder: 2)
        context.insert(cash)
        context.insert(debit)
        context.insert(credit)

        try? context.save()
    }
}
