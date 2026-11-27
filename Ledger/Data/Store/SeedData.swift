import Foundation
import SwiftData

/// 首次启动与升级时的内置数据。
/// 分类刻意保持「宽口径」——覆盖要全，但一屏能扫完，避免记账时选择困难。
enum SeedData {
    struct CategorySeed {
        let name: String
        let emoji: String
    }

    private static let versionKey = "seed.categories.version"
    static let currentVersion = 7

    static let expenseCategories: [CategorySeed] = [
        CategorySeed(name: "餐饮", emoji: "🍜"),
        CategorySeed(name: "交通", emoji: "🚇"),
        CategorySeed(name: "购物", emoji: "🛍️"),
        CategorySeed(name: "日用", emoji: "🧻"),
        CategorySeed(name: "居住", emoji: "🏠"),
        CategorySeed(name: "房租", emoji: "🔑"),
        CategorySeed(name: "水费", emoji: "🚰"),
        CategorySeed(name: "电费", emoji: "⚡"),
        CategorySeed(name: "燃气费", emoji: "🔥"),
        CategorySeed(name: "物业费", emoji: "🏢"),
        CategorySeed(name: "通讯", emoji: "📱"),
        CategorySeed(name: "娱乐", emoji: "🎮"),
        CategorySeed(name: "医疗", emoji: "💊"),
        CategorySeed(name: "教育", emoji: "📚"),
        CategorySeed(name: "人情", emoji: "🎁"),
        CategorySeed(name: "旅行", emoji: "✈️"),
        CategorySeed(name: "宠物", emoji: "🐱"),
        CategorySeed(name: "母婴", emoji: "🍼"),
        CategorySeed(name: "订阅服务", emoji: "🔔"),
        CategorySeed(name: "运动健身", emoji: "🏃"),
        CategorySeed(name: "捐款", emoji: "🤝"),
        CategorySeed(name: "利息支出", emoji: "🏦"),
        CategorySeed(name: "手续费", emoji: "🧾"),
        CategorySeed(name: "保险", emoji: "🛡️"),
        CategorySeed(name: "税费", emoji: "📊"),
        CategorySeed(name: "报销差额", emoji: "📎"),
        CategorySeed(name: "其他", emoji: "📦")
    ]

    static let incomeCategories: [CategorySeed] = [
        CategorySeed(name: "工资", emoji: "💰"),
        CategorySeed(name: "奖金", emoji: "🏆"),
        CategorySeed(name: "兼职", emoji: "💼"),
        CategorySeed(name: "报销收入", emoji: "🧾"),
        CategorySeed(name: "投资收益", emoji: "📈"),
        CategorySeed(name: "利息收入", emoji: "🏦"),
        CategorySeed(name: "红包", emoji: "🧧"),
        CategorySeed(name: "退款", emoji: "↩️"),
        CategorySeed(name: "其他", emoji: "📦")
    ]

    /// 幂等：首次建库，或按版本号补齐分类。
    /// 开发期不保留历史数据迁移逻辑，避免包袱；正式使用前会清库重来。
    static func bootstrapIfNeeded(context: ModelContext) {
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []

        if books.isEmpty {
            createDefaultData(context: context)
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
            return
        }

        let storedVersion = UserDefaults.standard.integer(forKey: versionKey)
        guard storedVersion < currentVersion else { return }

        for book in books where book.deletedAt == nil {
            topUpCategories(context: context, bookId: book.id)
        }
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }

    private static func createDefaultData(context: ModelContext) {
        let book = Book()
        context.insert(book)

        insertCategories(expenseCategories, kind: .expense, bookId: book.id, startOrder: 0, context: context)
        insertCategories(incomeCategories, kind: .income, bookId: book.id, startOrder: 0, context: context)

        let cash = Account(bookId: book.id, name: "现金", type: .cash, iconEmoji: "💵", sortOrder: 0)
        let debit = Account(bookId: book.id, name: "储蓄卡", type: .debit, iconEmoji: "🏦", sortOrder: 1)
        let credit = Account(bookId: book.id, name: "信用卡", type: .credit, iconEmoji: "💳", colorHex: "C98A9B", sortOrder: 2)
        cash.bankId = "cash"
        debit.bankId = "other"
        credit.bankId = "other"
        context.insert(cash)
        context.insert(debit)
        context.insert(credit)

        try? context.save()
    }

    private static func insertCategories(
        _ seeds: [CategorySeed],
        kind: CategoryKind,
        bookId: UUID,
        startOrder: Int,
        context: ModelContext
    ) {
        for (offset, seed) in seeds.enumerated() {
            let category = Category(
                bookId: bookId,
                name: seed.name,
                kind: kind,
                iconEmoji: seed.emoji,
                sortOrder: startOrder + offset,
                defaultReimbursable: seed.name == "交通" || seed.name == "旅行"
            )
            context.insert(category)
        }
    }

    /// 新建账本后立即补齐默认分类，不让用户面对无法分类的空白记账页。
    static func seedCategoriesIfNeeded(context: ModelContext, bookId: UUID) {
        topUpCategories(context: context, bookId: bookId)
    }

    /// 老用户升级：只补缺失的分类，不覆盖已有名称与排序偏好。
    private static func topUpCategories(context: ModelContext, bookId: UUID) {
        let existing = ((try? context.fetch(FetchDescriptor<Category>())) ?? []).filter { $0.bookId == bookId }
        // 归档分类也算「已存在」：否则 seed 升级或新建账本时会把归档项复活成同名重复分类。
        let existingExpense = Set(existing.filter { $0.kind == .expense && $0.deletedAt == nil }.map { $0.name })
        let existingIncome = Set(existing.filter { $0.kind == .income && $0.deletedAt == nil }.map { $0.name })

        var order = (existing.filter { $0.kind == .expense }.map { $0.sortOrder }.max() ?? 0) + 1
        for seed in expenseCategories where !existingExpense.contains(seed.name) {
            let category = Category(
                bookId: bookId,
                name: seed.name,
                kind: .expense,
                iconEmoji: seed.emoji,
                sortOrder: order,
                defaultReimbursable: seed.name == "交通" || seed.name == "旅行"
            )
            context.insert(category)
            order += 1
        }

        order = (existing.filter { $0.kind == .income }.map { $0.sortOrder }.max() ?? 0) + 1
        for seed in incomeCategories where !existingIncome.contains(seed.name) {
            let category = Category(bookId: bookId, name: seed.name, kind: .income, iconEmoji: seed.emoji, sortOrder: order)
            context.insert(category)
            order += 1
        }

        try? context.save()
    }
}
