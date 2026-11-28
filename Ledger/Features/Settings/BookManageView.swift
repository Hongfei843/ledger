import SwiftUI
import SwiftData

/// 账本管理：新建、切换当前账本。
/// 说明：当前版本按账本区分的是「记账、明细、统计、资产、账户与分类」；
/// 贷款、报销、周期记账等模块暂为全局，后续版本再收敛。
struct BookManageView: View {
    @Environment(\.modelContext) private var context
    @Query private var books: [Book]
    @AppStorage(BookScope.key) private var currentBookRaw = ""

    @State private var showNew = false
    @State private var newName = ""

    private var liveBooks: [Book] {
        books
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private var currentId: UUID? { UUID(uuidString: currentBookRaw) }

    var body: some View {
        List {
            Section {
                ForEach(liveBooks, id: \.id) { book in
                    Button {
                        BookScope.setCurrent(book.id)
                        Haptics.selection()
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Text(book.iconEmoji)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.name)
                                    .foregroundStyle(.primary)
                                Text(book.id == currentId ? "当前账本" : "点按切换")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if book.id == currentId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("账本")
            } footer: {
                Text("当前版本：记账、明细、统计、资产、账户与分类按账本区分；贷款、报销、周期记账等仍为全局数据。")
            }

            Section {
                Button {
                    newName = ""
                    showNew = true
                } label: {
                    Label("新建账本", systemImage: "plus.circle")
                }
            } footer: {
                Text("适合把日常、家庭、副业分开记；新建后会立即切换过去。")
            }
        }
        .navigationTitle("账本管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let current = currentId, liveBooks.contains(where: { $0.id == current }) else {
                if let first = liveBooks.first {
                    BookScope.setCurrent(first.id)
                }
                return
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                Form {
                    Section {
                        TextField("账本名，如 家庭 / 副业", text: $newName)
                    }
                }
                .navigationTitle("新建账本")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showNew = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("创建") { createBook() }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func createBook() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let book = Book(
            name: name,
            iconEmoji: "📘",
            sortOrder: liveBooks.count,
            isDefault: liveBooks.isEmpty
        )
        context.insert(book)
        SeedData.seedCategoriesIfNeeded(context: context, bookId: book.id)
        PersistenceGuard.save(context, "账本管理")
        BookScope.setCurrent(book.id)
        showNew = false
        Haptics.success()
    }
}
