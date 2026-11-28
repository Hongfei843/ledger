import SwiftUI
import SwiftData

struct AccountEditView: View {
    /// nil 表示新建
    let account: Account?

    // 新建时的预填（用于 OCR 识别付款方式后一键添加）
    var prefillName: String = ""
    var prefillBankId: String? = nil
    var prefillCardTail: String = ""
    var prefillType: AccountType? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]
    @Query private var allAccounts: [Account]
    @Query private var allTxns: [Txn]

    @State private var name = ""
    @State private var bankId: String?
    @State private var cardTail = ""
    @State private var type: AccountType = .debit
    @State private var balanceText = "0"
    @State private var includeInNetWorth = true
    @State private var costText = ""
    @State private var showBankPicker = false
    @State private var showDeleteConfirm = false
    @State private var showArchiveConfirm = false

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

                if type == .investment {
                    Section {
                        TextField("持仓成本（元，可选）", text: $costText)
                            .keyboardType(.numbersAndPunctuation)
                    } header: {
                        Text("投资持仓")
                    } footer: {
                        Text("填买入成本后，账户详情和资产页会显示浮动盈亏、收益率；不填则只显示市值。")
                    }
                }

                if isEditing, let account {
                    Section {
                        Button("归档该账户") { showArchiveConfirm = true }
                        Button("删除该账户", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    } footer: {
                        Text(deleteFooter(account))
                    }
                }

                if isEditing, let account, account.isArchived {
                    Section {
                        Button("恢复该账户") {
                            account.isArchived = false
                            account.updatedAt = Date()
                            PersistenceGuard.save(context, "账户编辑")
                            Haptics.success()
                            dismiss()
                        }
                    } footer: {
                        Text("恢复后会重新出现在记账账户条、资产与对账页。")
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
            .confirmationDialog("归档账户", isPresented: $showArchiveConfirm, titleVisibility: .visible) {
                Button("归档", role: .destructive) {
                    account?.isArchived = true
                    account?.updatedAt = Date()
                    PersistenceGuard.save(context, "账户编辑")
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("归档后账户会从记账、资产与对账中隐藏；可在账户管理里恢复。")
            }
            .confirmationDialog("删除后历史流水仍保留，确定？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    account?.deletedAt = Date()
                    account?.updatedAt = Date()
                    PersistenceGuard.save(context, "账户编辑")
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear(perform: load)
        }
    }

    private func deleteFooter(_ account: Account) -> String {
        let count = allTxns.filter {
            $0.deletedAt == nil && ($0.accountId == account.id || $0.counterAccountId == account.id)
        }.count
        if count == 0 {
            return "该账户还没有流水，删除不影响任何记录。归档后不再出现在记账与对账里。"
        }
        return "该账户有 \(count) 笔历史流水。删除后这些记录完整保留（明细里仍显示账户名），只是不能再选它记账。卡停用、平台注销时用删除更合适。"
    }

    private func load() {
        guard let account else {
            if !prefillName.isEmpty {
                name = prefillName
                bankId = prefillBankId
                cardTail = prefillCardTail
                type = prefillType ?? type
            }
            return
        }
        name = account.name
        bankId = account.bankId
        cardTail = account.cardTail ?? ""
        type = account.type
        balanceText = Money.rawText(account.openingBalanceMinor)
        includeInNetWorth = account.includeInNetWorth
        costText = account.positionCostMinor.map { Money.rawText($0) } ?? ""
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let tail = String(cardTail.filter { $0.isNumber }.prefix(4))
        let opening = Money.parse(balanceText) ?? 0
        let cost = Money.parse(costText)
        let preset = BankPreset.find(bankId)

        if let account {
            account.name = trimmedName
            account.bankId = bankId
            account.cardTail = tail.isEmpty ? nil : tail
            account.type = type
            account.openingBalanceMinor = opening
            account.includeInNetWorth = includeInNetWorth
            account.positionCostMinor = type == .investment ? cost : nil
            account.iconEmoji = preset?.short.isEmpty == false ? "🏦" : account.iconEmoji
            if let preset { account.colorHex = preset.colorHex }
            account.updatedAt = Date()
        } else {
            let bookId = BookScope.currentId ?? books.first?.id ?? UUID()
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
            created.positionCostMinor = type == .investment ? cost : nil
            context.insert(created)
        }

        PersistenceGuard.save(context, "账户编辑")

        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        PersistenceGuard.save(context, "账户编辑")

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
