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
    static let currentVersion = 5

    static let expenseCategories: [CategorySeed] = [
        CategorySeed(name: "餐饮", emoji: "🍜"),
        CategorySeed(name: "交通", emoji: "🚇"),
        CategorySeed(name: "购物", emoji: "🛍️"),
        CategorySeed(name: "日用", emoji: "🧻"),
        CategorySeed(name: "居住", emoji: "🏠"),
        CategorySeed(name: "房租", emoji: "🔑"),
        CategorySeed(name: "水电燃气", emoji: "💡"),
        CategorySeed(name: "通讯", emoji: "📱"),
        CategorySeed(name: "娱乐", emoji: "🎮"),
        CategorySeed(name: "医疗", emoji: "💊"),
        CategorySeed(name: "教育", emoji: "📚"),
        CategorySeed(name: "人情", emoji: "🎁"),
        CategorySeed(name: "旅行", emoji: "✈️"),
        CategorySeed(name: "宠物", emoji: "🐱"),
        CategorySeed(name: "母婴", emoji: "🍼"),
        CategorySeed(name: "订阅服务", emoji: "🔔"),
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
        CategorySeed(name: "红包", emoji: "🧧"),
        CategorySeed(name: "退款", emoji: "↩️"),
        CategorySeed(name: "其他", emoji: "📦")
    ]

    /// 旧分类 → 新分类。升级时把流水迁过去，旧分类归档。
    private static let mergeMap: [String: String] = [
        // 支出
        "咖啡奶茶": "餐饮", "外卖": "餐饮", "买菜": "餐饮", "水果": "餐饮", "零食": "餐饮", "烟酒": "餐饮",
        "打车": "交通", "公交地铁": "交通", "加油": "交通", "停车": "交通",
        "服饰": "购物", "美妆": "购物", "数码": "购物", "家装": "购物",
        "物业": "居住", "宽带": "居住", "电费": "水电燃气", "水费": "水电燃气",
        "电影": "娱乐", "健身": "娱乐",
        "药品": "医疗", "体检": "医疗",
        "书籍": "教育",
        "住宿": "旅行",
        "话费": "通讯",
        "人情送礼": "人情",
        "App 订阅": "订阅服务",
        // 收入
        "年终奖": "奖金", "利息收入": "投资收益", "礼金": "红包"
    ]

    /// 幂等：首次建库，或按版本号增量合并 + 补齐分类。
    static func bootstrapIfNeeded(context: ModelContext) {
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []

        if books.isEmpty {
            createDefaultData(context: context)
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
            return
        }

        let storedVersion = UserDefaults.standard.integer(forKey: versionKey)
        guard storedVersion < currentVersion else { return }
        guard let book = books.first else { return }

        consolidateCategories(context: context, bookId: book.id)
        topUpCategories(context: context, bookId: book.id)
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }

    /// v4：把细分分类合并进大类，流水一并迁移
    private static func consolidateCategories(context: ModelContext, bookId: UUID) {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let txns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        var maxSort = (categories.map { $0.sortOrder }.max() ?? 0) + 1

        for (oldName, newName) in mergeMap where oldName != newName {
            guard let source = categories.first(where: { $0.name == oldName && $0.kind == .expense && $0.deletedAt == nil }) else {
                continue
            }
            let target: Category
            if let existing = categories.first(where: { $0.name == newName && $0.kind == .expense && $0.deletedAt == nil }) {
                target = existing
            } else {
                let created = Category(bookId: bookId, name: newName, kind: .expense, sortOrder: maxSort)
                maxSort += 1
                context.insert(created)
                target = created
            }

            for txn in txns where txn.categoryId == source.id {
                txn.categoryId = target.id
                txn.updatedAt = Date()
            }
            source.isArchived = true
            source.updatedAt = Date()
        }

        // 收入侧合并
        for (oldName, newName) in [("年终奖", "奖金"), ("利息收入", "投资收益"), ("礼金", "红包")] {
            guard let source = categories.first(where: { $0.name == oldName && $0.kind == .income && $0.deletedAt == nil }) else {
                continue
            }
            let target: Category
            if let existing = categories.first(where: { $0.name == newName && $0.kind == .income && $0.deletedAt == nil }) {
                target = existing
            } else {
                let created = Category(bookId: bookId, name: newName, kind: .income, sortOrder: maxSort)
                maxSort += 1
                context.insert(created)
                target = created
            }
            for txn in txns where txn.categoryId == source.id {
                txn.categoryId = target.id
                txn.updatedAt = Date()
            }
            source.isArchived = true
            source.updatedAt = Date()
        }

        try? context.save()
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

    /// 老用户升级：只补缺失的分类，不覆盖已有名称与排序偏好。
    private static func topUpCategories(context: ModelContext, bookId: UUID) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let existingExpense = Set(existing.filter { $0.kind == .expense && !$0.isArchived }.map { $0.name })
        let existingIncome = Set(existing.filter { $0.kind == .income && !$0.isArchived }.map { $0.name })

        var order = (existing.filter { $0.kind == .expense }.map { $0.sortOrder }.max() ?? 0) + 1
        for seed in expenseCategories where !existingExpense.contains(seed.name) {
            let category = Category(bookId: bookId, name: seed.name, kind: .expense, iconEmoji: seed.emoji, sortOrder: order)
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
