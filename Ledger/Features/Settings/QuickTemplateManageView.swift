import SwiftUI
import SwiftData

/// 常用组合管理：增删改；「记一笔」里也能直接存。
struct QuickTemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query private var templates: [QuickTemplate]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var editing: QuickTemplate?
    @State private var showAdd = false

    private var live: [QuickTemplate] {
        templates
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section {
                if live.isEmpty {
                    Text("还没有常用组合。\n在「记一笔」里填好金额和分类后，点右上角「···」→ 保存为常用组合。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(live, id: \.id) { template in
                    Button {
                        editing = template
                    } label: {
                        row(template)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            template.deletedAt = Date()
                            template.updatedAt = Date()
                            try? context.save()
                        } label: {
                            Text("删除")
                        }
                    }
                }
            } footer: {
                Text("点一下编辑，左滑删除。记一笔时点模板即可一键套用。")
            }
        }
        .navigationTitle("常用组合")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { template in
            QuickTemplateEditView(template: template)
        }
        .sheet(isPresented: $showAdd) {
            QuickTemplateEditView(template: nil)
        }
    }

    private func row(_ template: QuickTemplate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(template.name)
                    .font(.subheadline)
                Spacer()
                if let amount = template.amountMinor, amount > 0 {
                    Text(Money.format(amount))
                        .font(Theme.Fonts.amountM)
                        .monospacedDigit()
                }
            }
            Text(detailLine(template))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func detailLine(_ template: QuickTemplate) -> String {
        var parts: [String] = [template.type.displayName]
        if let categoryId = template.categoryId,
           let category = categories.first(where: { $0.id == categoryId }) {
            parts.append(category.name)
        }
        if let accountId = template.accountId,
           let account = accounts.first(where: { $0.id == accountId }) {
            parts.append(account.displayName)
        }
        if let payee = template.payee, !payee.isEmpty { parts.append(payee) }
        if let note = template.note, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

/// 新建 / 编辑常用组合
struct QuickTemplateEditView: View {
    let template: QuickTemplate?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var name = ""
    @State private var type: TxnType = .expense
    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var payee = ""
    @State private var note = ""

    init(template: QuickTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _type = State(initialValue: template?.type ?? .expense)
        _amountText = State(initialValue: template?.amountMinor.map { Money.rawText($0) } ?? "")
        _accountId = State(initialValue: template?.accountId)
        _categoryId = State(initialValue: template?.categoryId)
        _payee = State(initialValue: template?.payee ?? "")
        _note = State(initialValue: template?.note ?? "")
    }

    private var activeAccounts: [Account] {
        accounts
            .filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectableCategories: [Category] {
        let kind: CategoryKind = type == .income ? .income : .expense
        return categories
            .filter { $0.deletedAt == nil && !$0.isArchived && $0.kind == kind }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如 星巴克拿铁", text: $name)
                }

                Section("内容") {
                    Picker("类型", selection: $type) {
                        Text("支出").tag(TxnType.expense)
                        Text("收入").tag(TxnType.income)
                        Text("转账").tag(TxnType.transfer)
                    }
                    if type != .transfer {
                        TextField("金额（可选，元）", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                    Picker("账户", selection: $accountId) {
                        Text("不指定").tag(UUID?.none)
                        ForEach(activeAccounts, id: \.id) { account in
                            Text(account.displayName).tag(UUID?.some(account.id))
                        }
                    }
                    if type != .transfer {
                        Picker("分类", selection: $categoryId) {
                            Text("不指定").tag(UUID?.none)
                            ForEach(selectableCategories, id: \.id) { category in
                                Text("\(category.iconEmoji) \(category.name)").tag(UUID?.some(category.id))
                            }
                        }
                    }
                }

                Section("其它（可选）") {
                    TextField("商家 / 对方", text: $payee)
                    TextField("备注", text: $note)
                }
            }
            .navigationTitle(template == nil ? "新建常用组合" : "编辑常用组合")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = Money.parse(amountText)
        let validAmount: Int64? = {
            guard let amount, amount > 0 else { return nil }
            return amount
        }()

        if let template {
            template.name = trimmedName
            template.type = type
            template.amountMinor = validAmount
            template.accountId = accountId
            template.categoryId = type == .transfer ? nil : categoryId
            template.payee = payee.isEmpty ? nil : payee
            template.note = note.isEmpty ? nil : note
            template.updatedAt = Date()
        } else {
            let nextOrder = (try? context.fetch(FetchDescriptor<QuickTemplate>()).map { $0.sortOrder }.max()) ?? nil
            let created = QuickTemplate(
                bookId: books.first?.id ?? UUID(),
                name: trimmedName,
                type: type,
                amountMinor: validAmount,
                accountId: accountId,
                categoryId: type == .transfer ? nil : categoryId,
                payee: payee.isEmpty ? nil : payee,
                note: note.isEmpty ? nil : note,
                sortOrder: (nextOrder ?? 0) + 1
            )
            context.insert(created)
        }

        try? context.save()
        Haptics.success()
        dismiss()
    }
}
