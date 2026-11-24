import SwiftUI
import SwiftData

struct AccountEditView: View {
    /// nil 表示新建
    let account: Account?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]
    @Query private var allAccounts: [Account]

    @State private var name = ""
    @State private var bankId: String?
    @State private var cardTail = ""
    @State private var type: AccountType = .debit
    @State private var balanceText = "0"
    @State private var includeInNetWorth = true
    @State private var showBankPicker = false
    @State private var showDeleteConfirm = false

    private var selectedBank: BankPreset? {
        BankPreset.find(bankId)
    }

    private var isEditing: Bool { account != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("银行 / 平台") {
                    Button {
                        showBankPicker = true
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            BankMarkView(
                                bankId: bankId,
                                fallbackEmoji: account?.iconEmoji ?? "💳",
                                fallbackColorHex: account?.colorHex ?? "5B7C99",
                                size: 36
                            )
                            Text(selectedBank?.name ?? "选择银行或平台")
                                .foregroundStyle(selectedBank == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    TextField("账户名，如 招行工资卡", text: $name)
                    TextField("卡号后四位（可选）", text: $cardTail)
                        .keyboardType(.numberPad)
                } header: {
                    Text("名称")
                } footer: {
                    Text("同一家银行有多张卡时，填后四位就能区分，列表里会显示为「招行储蓄卡 ••1234」。")
                }

                Section("类型") {
                    Picker("类型", selection: $type) {
                        ForEach(AccountType.allCases.filter { $0 != .loan }, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }

                Section {
                    TextField("期初余额", text: $balanceText)
                        .keyboardType(.numbersAndPunctuation)
                    Toggle("计入净资产", isOn: $includeInNetWorth)
                } header: {
                    Text(isEditing ? "期初余额（修改会影响当前余额）" : "期初余额")
                }

                if isEditing, let account {
                    Section {
                        Button("归档该账户") {
                            account.isArchived = true
                            account.updatedAt = Date()
                            try? context.save()
                            dismiss()
                        }
                        Button("删除该账户", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    } footer: {
                        Text("归档后不再出现在记账与对账里，历史流水保留。删除是软删除，同样保留历史。")
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑账户" : "新建账户")
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
            .sheet(isPresented: $showBankPicker) {
                BankPickerView(selectedId: $bankId, type: $type, name: $name, cardTail: $cardTail)
            }
            .confirmationDialog("删除后历史流水仍保留，确定？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    account?.deletedAt = Date()
                    account?.updatedAt = Date()
                    try? context.save()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let account else { return }
        name = account.name
        bankId = account.bankId
        cardTail = account.cardTail ?? ""
        type = account.type
        balanceText = Money.rawText(account.openingBalanceMinor)
        includeInNetWorth = account.includeInNetWorth
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let tail = String(cardTail.filter { $0.isNumber }.prefix(4))
        let opening = Money.parse(balanceText) ?? 0
        let preset = BankPreset.find(bankId)

        if let account {
            account.name = trimmedName
            account.bankId = bankId
            account.cardTail = tail.isEmpty ? nil : tail
            account.type = type
            account.openingBalanceMinor = opening
            account.includeInNetWorth = includeInNetWorth
            account.iconEmoji = preset?.short.isEmpty == false ? "🏦" : account.iconEmoji
            if let preset { account.colorHex = preset.colorHex }
            account.updatedAt = Date()
        } else {
            let bookId = books.first?.id ?? UUID()
            let created = Account(
                bookId: bookId,
                name: trimmedName,
                type: type,
                openingBalanceMinor: opening,
                iconEmoji: "🏦",
                colorHex: preset?.colorHex ?? "5B7C99",
                sortOrder: allAccounts.count
            )
            created.bankId = bankId
            created.cardTail = tail.isEmpty ? nil : tail
            created.includeInNetWorth = includeInNetWorth
            context.insert(created)
        }

        try? context.save()

        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        try? context.save()

        Haptics.success()
        dismiss()
    }
}

// MARK: - 银行选择

struct BankPickerView: View {
    @Binding var selectedId: String?
    @Binding var type: AccountType
    @Binding var name: String
    @Binding var cardTail: String

    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""

    private var banks: [BankPreset] {
        filtered.filter { ["cmb", "icbc", "ccb", "abc", "boc", "bocom", "psbc", "citic", "spdb", "cmbc", "cib", "ceb", "hxb", "cgb", "pab", "bosh", "bob", "nbcb", "webank", "mybank"].contains($0.id) }
    }

    private var platforms: [BankPreset] {
        filtered.filter { !banks.contains($0) }
    }

    private var filtered: [BankPreset] {
        let base = BankPreset.all
        guard !keyword.isEmpty else { return base }
        return base.filter { $0.name.contains(keyword) || $0.short.contains(keyword) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("银行") {
                    ForEach(banks) { preset in
                        row(preset)
                    }
                }
                Section("平台 / 其他") {
                    ForEach(platforms) { preset in
                        row(preset)
                    }
                }
            }
            .searchable(text: $keyword, prompt: "搜索银行或平台")
            .navigationTitle("选择")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func row(_ preset: BankPreset) -> some View {
        Button {
            selectedId = preset.id
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                let tail = cardTail.isEmpty ? "" : " \(cardTail)"
                name = preset.name + tail
            }
            if type != preset.suggestedType {
                type = preset.suggestedType
            }
            Haptics.selection()
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                BankMarkView(bankId: preset.id, fallbackEmoji: "💳", fallbackColorHex: preset.colorHex, size: 32)
                Text(preset.name)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedId == preset.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
