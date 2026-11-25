import SwiftUI
import SwiftData

struct CategoryManageView: View {
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]
    @Query private var books: [Book]
    @Query private var txns: [Txn]

    @State private var editing: Category?
    @State private var showNew = false

    private var usage: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for txn in txns where txn.deletedAt == nil {
            guard let categoryId = txn.categoryId else { continue }
            counts[categoryId, default: 0] += 1
        }
        return counts
    }

    private var expense: [Category] {
        categories
            .filter { $0.deletedAt == nil && !$0.isArchived && $0.kind == .expense }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var income: [Category] {
        categories
            .filter { $0.deletedAt == nil && !$0.isArchived && $0.kind == .income }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var archived: [Category] {
        categories
            .filter { $0.deletedAt == nil && $0.isArchived }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            section(title: "支出分类", items: expense)
            section(title: "收入分类", items: income)

            if !archived.isEmpty {
                Section("已归档") {
                    ForEach(archived, id: \.id) { category in
                        HStack {
                            Text(category.iconEmoji)
                            Text(category.name)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("恢复") {
                                category.isArchived = false
                                category.updatedAt = Date()
                                try? context.save()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("分类管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNew) {
            CategoryEditSheet(category: nil)
                .presentationDetents([.medium])
        }
        .sheet(item: $editing) { category in
            CategoryEditSheet(category: category)
                .presentationDetents([.medium])
        }
    }

    private func section(title: String, items: [Category]) -> some View {
        Section(title) {
            ForEach(items, id: \.id) { category in
                HStack(spacing: Theme.Spacing.s) {
                    Button {
                        editing = category
                    } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            Text(category.iconEmoji)
                            Text(category.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if let count = usage[category.id], count > 0 {
                                Text("\(count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CategoryTxnListView(
                            categoryId: category.id,
                            range: DateInterval(
                                start: Date.distantPast,
                                end: Date().addingTimeInterval(86400)
                            ),
                            title: category.name
                        )
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看该分类的条目")
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        category.isArchived = true
                        category.updatedAt = Date()
                        try? context.save()
                    } label: {
                        Text("归档")
                    }
                }
            }
        }
    }
}

struct CategoryEditSheet: View {
    /// nil 表示新建
    let category: Category?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]

    @State private var name = ""
    @State private var emoji = "📦"
    @State private var kind: CategoryKind = .expense

    private let emojiOptions = [
        "🍜", "☕", "🥡", "🥬", "🍎", "🍰", "🍷", "🚇", "🚕", "🚌",
        "⛽", "🅿️", "🛍️", "👕", "💄", "💻", "🧻", "🔨", "🏠", "🏢",
        "💡", "📶", "📱", "🎮", "🎬", "🏃", "💊", "💉", "🩺", "🛡️",
        "📚", "📖", "🎁", "✈️", "🏨", "🐱", "🔔", "🏦", "🧾", "📎",
        "📊", "📦", "💰", "🏆", "🎊", "💼", "📈", "💹", "🧧", "↩️"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("分类名", text: $name)
                }
                Section("类型") {
                    Picker("类型", selection: $kind) {
                        Text("支出").tag(CategoryKind.expense)
                        Text("收入").tag(CategoryKind.income)
                    }
                    .pickerStyle(.segmented)
                    .disabled(category != nil)
                }
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                        ForEach(emojiOptions, id: \.self) { item in
                            Button {
                                emoji = item
                            } label: {
                                Text(item)
                                    .font(.system(size: 20))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        emoji == item ? Theme.accent.opacity(0.16) : Color.clear,
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(category == nil ? "新建分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let category {
                    name = category.name
                    emoji = category.iconEmoji
                    kind = category.kind
                }
            }
        }
    }

    private func save() {
        if let category {
            category.name = name.trimmingCharacters(in: .whitespaces)
            category.iconEmoji = emoji
            category.updatedAt = Date()
        } else {
            let bookId = books.first?.id ?? UUID()
            let maxOrder = ((try? context.fetch(FetchDescriptor<Category>())) ?? []).map { $0.sortOrder }.max() ?? 0
            let created = Category(
                bookId: bookId,
                name: name.trimmingCharacters(in: .whitespaces),
                kind: kind,
                iconEmoji: emoji,
                sortOrder: maxOrder + 1
            )
            context.insert(created)
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
