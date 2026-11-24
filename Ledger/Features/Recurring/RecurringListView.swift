import SwiftUI
import SwiftData

struct RecurringListView: View {
    @Environment(\.modelContext) private var context
    @Query private var rules: [RecurringRule]
    @State private var showNew = false
    @State private var editing: RecurringRule?

    private var activeRules: [RecurringRule] {
        rules.filter { $0.deletedAt == nil }.sorted { $0.nextDate < $1.nextDate }
    }

    var body: some View {
        List {
            Section {
                if activeRules.isEmpty {
                    Text("还没有周期记账")
                        .foregroundStyle(.secondary)
                }
                ForEach(activeRules, id: \.id) { rule in
                    Button {
                        editing = rule
                    } label: {
                        row(rule)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            rule.deletedAt = Date()
                            rule.updatedAt = Date()
                            try? context.save()
                        } label: {
                            Text("删除")
                        }
                        Button {
                            rule.isPaused.toggle()
                            rule.updatedAt = Date()
                            try? context.save()
                        } label: {
                            Text(rule.isPaused ? "启用" : "暂停")
                        }
                        .tint(Theme.warning)
                    }
                }
            } footer: {
                Text("开启「自动生成」后，每次打开 App 会把到今天为止该记的都补上（单次最多 40 条）。适合房租、订阅、还款、公积金缴存这类固定支出。")
            }
        }
        .navigationTitle("周期记账")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNew) {
            RecurringEditView(rule: nil)
        }
        .sheet(item: $editing) { rule in
            RecurringEditView(rule: rule)
        }
    }

    private func row(_ rule: RecurringRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rule.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(Money.format(rule.amountMinor))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            HStack {
                Text("\(rule.frequency.displayName) · \(rule.templateType.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(rule.isPaused ? "已暂停" : "下次 \(DateFormatter.ledgerShort.string(from: rule.nextDate))")
                    .font(.caption2)
                    .foregroundStyle(rule.isPaused ? .secondary : Theme.accent)
            }
            if !rule.autoCreate {
                Text("未开启自动生成")
                    .font(.caption2)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecurringEditView: View {
    let rule: RecurringRule?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var books: [Book]

    @State private var title = ""
    @State private var type: TxnType = .expense
    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var startDate = Date()
    @State private var autoCreate = true
    @State private var note = ""

    private var selectableAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
    }

    private var selectableCategories: [Category] {
        let kind: CategoryKind = type == .income ? .income : .expense
        return categories.filter { $0.deletedAt == nil && !$0.isArchived && $0.kind == kind }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如 房租、视频会员", text: $title)
                }

                Section("金额与类型") {
                    Picker("类型", selection: $type) {
                        Text("支出").tag(TxnType.expense)
                        Text("收入").tag(TxnType.income)
                    }
                    .pickerStyle(.segmented)
                    TextField("金额（元）", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section("账户与分类") {
                    Picker("账户", selection: $accountId) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(selectableAccounts, id: \.id) { account in
                            Text(account.displayName).tag(UUID?.some(account.id))
                        }
                    }
                    Picker("分类", selection: $categoryId) {
                        Text("不指定").tag(UUID?.none)
                        ForEach(selectableCategories, id: \.id) { category in
                            Text(category.name).tag(UUID?.some(category.id))
                        }
                    }
                }

                Section("频率") {
                    Picker("频率", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    Toggle("自动生成", isOn: $autoCreate)
                }

                Section("备注") {
                    TextField("可选", text: $note)
                }
            }
            .navigationTitle(rule == nil ? "新建周期记账" : "编辑")
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
            .onAppear(perform: load)
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (Money.parse(amountText) ?? 0) > 0
            && accountId != nil
    }

    private func load() {
        guard let rule else {
            accountId = selectableAccounts.first?.id
            return
        }
        title = rule.title
        type = rule.templateType
        amountText = Money.rawText(rule.amountMinor)
        accountId = rule.accountId
        categoryId = rule.categoryId
        frequency = rule.frequency
        startDate = rule.startDate
        autoCreate = rule.autoCreate
        note = rule.note ?? ""
    }

    private func save() {
        guard let accountId, let amount = Money.parse(amountText), amount > 0 else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)

        if let rule {
            rule.title = trimmed
            rule.templateType = type
            rule.amountMinor = amount
            rule.accountId = accountId
            rule.categoryId = categoryId
            rule.frequency = frequency
            rule.startDate = startDate
            rule.autoCreate = autoCreate
            rule.note = note.isEmpty ? nil : note
            rule.updatedAt = Date()
        } else {
            let bookId = books.first?.id ?? UUID()
            let created = RecurringRule(
                bookId: bookId,
                title: trimmed,
                templateType: type,
                amountMinor: amount,
                accountId: accountId,
                frequency: frequency,
                startDate: startDate
            )
            created.categoryId = categoryId
            created.autoCreate = autoCreate
            created.note = note.isEmpty ? nil : note
            context.insert(created)
        }

        try? context.save()
        Haptics.success()
        dismiss()
    }
}
