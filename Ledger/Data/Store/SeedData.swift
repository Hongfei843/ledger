import Foundation
import SwiftData

/// 首次启动与升级时的内置数据。
/// 分类扩充通过 seedVersion 增量补齐，老用户升级也能拿到新分类，不重复插入。
enum SeedData {
    struct CategorySeed {
        let name: String
        let emoji: String
        let symbol: String
    }

    private static let versionKey = "seed.categories.version"
    static let currentVersion = 3

    static let expenseCategories: [CategorySeed] = [
        CategorySeed(name: "餐饮", emoji: "🍜", symbol: "fork.knife"),
        CategorySeed(name: "咖啡奶茶", emoji: "☕", symbol: "cup.and.saucer"),
        CategorySeed(name: "外卖", emoji: "🥡", symbol: "takeoutbag.and.cup.and.straw"),
        CategorySeed(name: "买菜", emoji: "🥬", symbol: "basket"),
        CategorySeed(name: "水果", emoji: "🍎", symbol: "leaf"),
        CategorySeed(name: "烟酒", emoji: "🍷", symbol: "wineglass"),
        CategorySeed(name: "交通", emoji: "🚇", symbol: "tram"),
        CategorySeed(name: "打车", emoji: "🚕", symbol: "car"),
        CategorySeed(name: "公交地铁", emoji: "🚌", symbol: "tram.fill"),
        CategorySeed(name: "加油", emoji: "⛽", symbol: "fuelpump"),
        CategorySeed(name: "停车", emoji: "🅿️", symbol: "parkingsign"),
        CategorySeed(name: "购物", emoji: "🛍️", symbol: "bag"),
        CategorySeed(name: "服饰", emoji: "👕", symbol: "tshirt"),
        CategorySeed(name: "美妆", emoji: "💄", symbol: "sparkles"),
        CategorySeed(name: "数码", emoji: "💻", symbol: "laptopcomputer"),
        CategorySeed(name: "日用", emoji: "🧻", symbol: "shippingbox"),
        CategorySeed(name: "家装", emoji: "🔨", symbol: "hammer"),
        CategorySeed(name: "居住", emoji: "🏠", symbol: "house"),
        CategorySeed(name: "物业", emoji: "🏢", symbol: "building.2"),
        CategorySeed(name: "水电燃气", emoji: "💡", symbol: "bolt"),
        CategorySeed(name: "宽带", emoji: "📶", symbol: "wifi"),
        CategorySeed(name: "话费", emoji: "📱", symbol: "antenna.radiowaves.left.and.right"),
        CategorySeed(name: "娱乐", emoji: "🎮", symbol: "gamecontroller"),
        CategorySeed(name: "电影", emoji: "🎬", symbol: "film"),
        CategorySeed(name: "健身", emoji: "🏃", symbol: "figure.run"),
        CategorySeed(name: "医疗", emoji: "💊", symbol: "cross.case"),
        CategorySeed(name: "药品", emoji: "💉", symbol: "pills"),
        CategorySeed(name: "体检", emoji: "🩺", symbol: "stethoscope"),
        CategorySeed(name: "保险", emoji: "🛡️", symbol: "shield"),
        CategorySeed(name: "教育", emoji: "📚", symbol: "graduationcap"),
        CategorySeed(name: "书籍", emoji: "📖", symbol: "books.vertical"),
        CategorySeed(name: "人情送礼", emoji: "🎁", symbol: "gift"),
        CategorySeed(name: "旅行", emoji: "✈️", symbol: "airplane"),
        CategorySeed(name: "住宿", emoji: "🏨", symbol: "bed.double"),
        CategorySeed(name: "宠物", emoji: "🐱", symbol: "pawprint"),
        CategorySeed(name: "订阅服务", emoji: "🔔", symbol: "bell"),
        CategorySeed(name: "利息支出", emoji: "🏦", symbol: "building.columns"),
        CategorySeed(name: "手续费", emoji: "🧾", symbol: "doc.text"),
        CategorySeed(name: "报销差额", emoji: "📎", symbol: "paperclip"),
        CategorySeed(name: "税费", emoji: "📊", symbol: "percent"),
        CategorySeed(name: "其他", emoji: "📦", symbol: "shippingbox")
    ]

    static let incomeCategories: [CategorySeed] = [
        CategorySeed(name: "工资", emoji: "💰", symbol: "banknote"),
        CategorySeed(name: "奖金", emoji: "🏆", symbol: "trophy"),
        CategorySeed(name: "年终奖", emoji: "🎊", symbol: "gift.fill"),
        CategorySeed(name: "兼职", emoji: "💼", symbol: "briefcase"),
        CategorySeed(name: "报销收入", emoji: "🧾", symbol: "doc.text.fill"),
        CategorySeed(name: "投资收益", emoji: "📈", symbol: "chart.line.uptrend.xyaxis"),
        CategorySeed(name: "利息收入", emoji: "💹", symbol: "percent"),
        CategorySeed(name: "红包", emoji: "🧧", symbol: "gift"),
        CategorySeed(name: "退款", emoji: "↩️", symbol: "arrow.uturn.backward"),
        CategorySeed(name: "礼金", emoji: "💌", symbol: "envelope"),
        CategorySeed(name: "其他", emoji: "📦", symbol: "shippingbox")
    ]

    /// 幂等：首次建库，或按版本号增量补齐分类。
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
        // v3：把「零食」并入「餐饮」，已有流水一并迁移
        if storedVersion < 3 {
            mergeSnackIntoDining(context: context, bookId: book.id)
        }
        topUpCategories(context: context, bookId: book.id)
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }

    /// 专用迁移：零食 → 餐饮（保留已有记录，不丢数据）
    private static func mergeSnackIntoDining(context: ModelContext, bookId: UUID) {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        guard let snack = categories.first(where: { $0.name == "零食" && $0.kind == .expense }) else {
            return
        }

        let dining: Category
        if let existing = categories.first(where: { $0.name == "餐饮" && $0.kind == .expense }) {
            dining = existing
        } else {
            let created = Category(bookId: bookId, name: "餐饮", kind: .expense, iconEmoji: "🍜", sortOrder: 0)
            context.insert(created)
            dining = created
        }

        let txns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        for txn in txns where txn.categoryId == snack.id {
            txn.categoryId = dining.id
            txn.updatedAt = Date()
        }

        snack.isArchived = true
        snack.updatedAt = Date()
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
                defaultReimbursable: seed.name == "交通" || seed.name == "打车" || seed.name == "公交地铁" || seed.name == "旅行" || seed.name == "住宿"
            )
            context.insert(category)
        }
    }

    /// 老用户升级：只补缺失的分类，不覆盖已有名称与排序偏好。
    private static func topUpCategories(context: ModelContext, bookId: UUID) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let existingExpense = Set(existing.filter { $0.kind == .expense }.map { $0.name })
        let existingIncome = Set(existing.filter { $0.kind == .income }.map { $0.name })

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
