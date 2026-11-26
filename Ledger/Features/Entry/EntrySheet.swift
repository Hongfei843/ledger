import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// 外部（截图识别 / 快捷指令 / 相册）带进来的预填值
struct EntrySheetPrefill {
    var amountMinor: Int64? = nil
    var payee: String? = nil
    var note: String? = nil
    var occurredAt: Date? = nil
    var accountId: UUID? = nil
    var hint: String? = nil
    var detectedBankId: String? = nil
    var detectedBankName: String? = nil
    var detectedCardTail: String? = nil
    var detectedAccountTypeRaw: String? = nil
}

extension EntrySheetPrefill {
    init(draft: ScreenshotImportDraft) {
        let hint: String
        if draft.amountMinor == nil {
            hint = "没识别出金额，请手动输入"
        } else if draft.confidence < 0.6 {
            hint = "截图识别置信度较低，请核对金额"
        } else {
            hint = "已从截图识别，请核对"
        }
        self.init(
            amountMinor: draft.amountMinor,
            payee: draft.payee,
            note: nil,
            occurredAt: nil,
            accountId: nil,
            hint: hint,
            detectedBankId: draft.bankId,
            detectedBankName: draft.bankName,
            detectedCardTail: draft.cardTail,
            detectedAccountTypeRaw: draft.paymentAccountTypeRaw
        )
    }
}

struct EntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var books: [Book]
    @Query private var claims: [Claim]
    @Query private var templates: [QuickTemplate]
    @Query private var statements: [Statement]
    @Query private var allTxns: [Txn]

    @State private var amountText = "0"
    @State private var selectedType: TxnType = .expense
    @State private var selectedCategoryId: UUID?
    @State private var selectedAccountId: UUID?
    @State private var counterAccountId: UUID?
    @State private var note = ""
    @State private var payee = ""
    @State private var occurredAt = Date()
    @State private var isReimbursable = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isRecognizing = false
    @State private var ocrHint: String?
    @State private var showSaveTemplate = false
    @State private var templateName = ""
    @State private var accountUsage: [UUID: Int] = [:]
    @State private var balanceCache: [UUID: Int64] = [:]
    @State private var showAddDetectedAccount = false
    @AppStorage(BookScope.key) private var currentBookRaw = ""

    /// 传入已有流水表示编辑模式；onSaved 用于父视图展示保存反馈
    private let editingTxn: Txn?
    private let prefill: EntrySheetPrefill?
    private let onSaved: ((String) -> Void)?

    init(editingTxn: Txn? = nil, prefill: EntrySheetPrefill? = nil, onSaved: ((String) -> Void)? = nil) {
        self.editingTxn = editingTxn
        self.prefill = prefill
        self.onSaved = onSaved

        let initialAmount: String
        if let editingTxn {
            initialAmount = Money.rawText(editingTxn.amountMinor)
        } else if let prefillAmount = prefill?.amountMinor, prefillAmount > 0 {
            initialAmount = Money.rawText(prefillAmount)
        } else {
            initialAmount = "0"
        }

        _amountText = State(initialValue: initialAmount)
        _selectedType = State(initialValue: editingTxn?.type ?? .expense)
        _selectedCategoryId = State(initialValue: editingTxn?.categoryId)
        _selectedAccountId = State(initialValue: editingTxn?.accountId ?? prefill?.accountId)
        _counterAccountId = State(initialValue: editingTxn?.counterAccountId)
        _note = State(initialValue: editingTxn?.note ?? prefill?.note ?? "")
        _payee = State(initialValue: editingTxn?.payee ?? prefill?.payee ?? "")
        _occurredAt = State(initialValue: editingTxn?.occurredAt ?? prefill?.occurredAt ?? Date())
        _isReimbursable = State(initialValue: editingTxn?.isReimbursable ?? false)
        _ocrHint = State(initialValue: editingTxn == nil ? prefill?.hint : nil)
    }

    // MARK: - 数据

    private var currentBookId: UUID? { UUID(uuidString: currentBookRaw) }
    private func bookMatches(_ id: UUID) -> Bool { BookScope.matches(id, raw: currentBookRaw) }

    private var baseAccounts: [Account] {
        let list = accounts.filter {
            $0.deletedAt == nil && !$0.isArchived && !$0.isSystem && bookMatches($0.bookId)
        }
        return AccountUsageService.orderedAccounts(list, usage: accountUsage)
    }

    private var filteredAccounts: [Account] {
        switch selectedType {
        case .income:
            return baseAccounts.filter { !$0.type.isLiability }
        default:
            return baseAccounts
        }
    }

    private var transferTargets: [Account] {
        baseAccounts.filter { $0.id != selectedAccountId }
    }

    /// OCR 识别到的付款方式
    private var detectedPaymentDraft: DetectedPaymentMethod? {
        guard let prefill, let bankName = prefill.detectedBankName, !bankName.isEmpty else { return nil }
        let type = prefill.detectedAccountTypeRaw.flatMap { AccountType(rawValue: $0) } ?? .debit
        return DetectedPaymentMethod(
            bankId: prefill.detectedBankId,
            bankName: bankName,
            accountType: type,
            cardTail: prefill.detectedCardTail
        )
    }

    /// 账户里是否已经有这张卡
    private var detectedMatchedAccount: Account? {
        guard let detected = detectedPaymentDraft else { return nil }
        if let tail = detected.cardTail, !tail.isEmpty {
            if let exact = filteredAccounts.first(where: { $0.cardTail == tail }) {
                return exact
            }
        }
        if let bankId = detected.bankId {
            return filteredAccounts.first { $0.bankId == bankId && $0.type == detected.accountType }
                ?? filteredAccounts.first { $0.bankId == bankId }
        }
        return nil
    }

    /// 每个分类的累计记账笔数。只在出现时算一次，避免每次渲染都扫全表。
    @State private var usageCache: [UUID: Int] = [:]

    private var usageCounts: [UUID: Int] { usageCache }

    private var filteredCategories: [Category] {
        let kind: CategoryKind = selectedType == .income ? .income : .expense
        let counts = usageCounts
        return categories
            .filter { $0.deletedAt == nil && !$0.isArchived && $0.kind == kind && bookMatches($0.bookId) }
            .sorted { lhs, rhs in
                let left = counts[lhs.id] ?? 0
                let right = counts[rhs.id] ?? 0
                if left != right { return left > right }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var amountMinor: Int64 {
        Money.parse(amountText) ?? 0
    }

    private var canSave: Bool {
        guard amountMinor > 0 else { return false }
        if selectedType == .transfer {
            return counterAccountId != nil && counterAccountId != selectedAccountId
        }
        return true
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                typePicker
                amountDisplay

                if editingTxn == nil, let detected = detectedPaymentDraft, detectedMatchedAccount == nil {
                    detectedPaymentBanner(detected)
                }

                if selectedType != .transfer, !activeTemplates.isEmpty {
                    templateStrip
                }

                if selectedType == .transfer {
                    transferSection
                } else {
                    accountStrip
                    categoryGrid
                }

                optionsRow
                Spacer(minLength: 0)
                bottomBar
            }
            .background(Theme.pageBackground)
            .navigationTitle(editingTxn == nil ? "记一笔" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        if isRecognizing {
                            ProgressView()
                        } else {
                            Image(systemName: "text.viewfinder")
                        }
                    }
                    .accessibilityLabel("从截图识别")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            templateName = defaultTemplateName()
                            showSaveTemplate = true
                        } label: {
                            Label("保存为常用组合", systemImage: "bolt.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await recognize(item) }
            }
            .onAppear(perform: prepareDefaults)
            .sheet(isPresented: $showAddDetectedAccount, onDismiss: {
                if let matched = detectedMatchedAccount {
                    selectedAccountId = matched.id
                }
            }) {
                if let detected = detectedPaymentDraft {
                    AccountEditView(
                        account: nil,
                        prefillName: detected.suggestedAccountName,
                        prefillBankId: detected.bankId,
                        prefillCardTail: detected.cardTail ?? "",
                        prefillType: detected.accountType
                    )
                }
            }
            .alert("保存为常用组合", isPresented: $showSaveTemplate) {
                TextField("名称，如 星巴克拿铁", text: $templateName)
                Button("保存") { saveAsTemplate() }
                Button("取消", role: .cancel) { templateName = "" }
            } message: {
                Text("会记住当前类型、金额、账户、分类、商家和备注，下次一键套用。")
            }
            .task {
                // 统计频次放到渲染之后，避免打开面板时卡顿
                var counts: [UUID: Int] = [:]
                for txn in allTxns where txn.deletedAt == nil {
                    guard let categoryId = txn.categoryId else { continue }
                    counts[categoryId, default: 0] += 1
                }
                usageCache = counts
                accountUsage = AccountUsageService.usageCounts(txns: allTxns)
                balanceCache = AccountUsageService.balanceMap(accounts: accounts, txns: allTxns)
            }
        }
    }

    private var typePicker: some View {
        Picker("类型", selection: $selectedType) {
            Text("支出").tag(TxnType.expense)
            Text("收入").tag(TxnType.income)
            Text("转账").tag(TxnType.transfer)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .onChange(of: selectedType) { _, _ in
            // 只在当前分类不适用新类型时才重置，套用「常用组合」时不会被覆盖
            if !filteredCategories.contains(where: { $0.id == selectedCategoryId }) {
                selectedCategoryId = filteredCategories.first?.id
            }
            if selectedType == .income, let current = selectedAccountId,
               !filteredAccounts.contains(where: { $0.id == current }) {
                selectedAccountId = filteredAccounts.first?.id
            }
            // 注意：不要在这里重置 isReimbursable。
            // 用户可能只是去看一眼收入分类再切回来，勾选状态应该保留。
        }
    }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Money.symbol)
                .font(Theme.Fonts.amount(22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(amountText)
                .font(Theme.Fonts.amount(40))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .overlay(alignment: .bottomLeading) {
            if let ocrHint {
                Text(ocrHint)
                    .font(.caption2)
                    .foregroundStyle(Theme.warning)
                    .padding(.leading, Theme.Spacing.l)
                    .padding(.bottom, 2)
            }
        }
    }

    private func detectedPaymentBanner(_ detected: DetectedPaymentMethod) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "creditcard")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("识别到付款方式：\(detected.displayName)")
                    .font(.caption)
                Text("账户里还没有这张卡，先添加账户或选择其他账户")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("添加") {
                showAddDetectedAccount = true
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var categoryGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                sectionTitle("常用")
                categoryGridContent(frequentCategories)

                if !remainingCategories.isEmpty {
                    sectionTitle("全部")
                    categoryGridContent(remainingCategories)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .frame(maxHeight: 224)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func categoryGridContent(_ items: [Category]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: Theme.Spacing.s) {
            ForEach(items, id: \.id) { category in
                categoryCell(category)
            }
        }
    }

    /// 常用：按历史使用频次取前 6 个（正好一行）；都没用过就取默认前 6 个
    private var frequentCategories: [Category] {
        let counts = usageCounts
        let used = filteredCategories
            .filter { (counts[$0.id] ?? 0) > 0 }
            .sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
        let top = Array(used.prefix(6))
        return top.isEmpty ? Array(filteredCategories.prefix(6)) : top
    }

    private var remainingCategories: [Category] {
        let ids = Set(frequentCategories.map { $0.id })
        return filteredCategories.filter { !ids.contains($0.id) }
    }

    private func categoryCell(_ category: Category) -> some View {
        let selected = selectedCategoryId == category.id
        return Button {
            selectedCategoryId = category.id
            Haptics.selection()
        } label: {
            VStack(spacing: 3) {
                CategoryIconView(category: category, size: 40)
                    .overlay(Circle().stroke(selected ? Theme.accent : Color.clear, lineWidth: 2))
                Text(category.name)
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .buttonStyle(.plain)
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            accountGroup(title: "转出账户", accounts: filteredAccounts, selection: $selectedAccountId)
            accountGroup(title: "转入账户", accounts: transferTargets, selection: $counterAccountId)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }

    private func accountGroup(title: String, accounts list: [Account], selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(list, id: \.id) { account in
                        accountChip(account, selection: selection)
                    }
                }
            }
        }
    }

    private var accountStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(filteredAccounts, id: \.id) { account in
                    accountChip(account, selection: $selectedAccountId)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .padding(.top, Theme.Spacing.s)
    }

    private func accountChip(_ account: Account, selection: Binding<UUID?>) -> some View {
        let selected = selection.wrappedValue == account.id
        let balance = balanceCache[account.id] ?? account.cachedBalanceMinor
        return Button {
            selection.wrappedValue = account.id
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                BankMarkView(
                    bankId: account.bankId,
                    fallbackEmoji: account.iconEmoji,
                    fallbackColorHex: account.colorHex,
                    size: 18
                )
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(account.displayName).font(.caption).lineLimit(1)
                        if account.type.isLiability {
                            Text("负债").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                    }
                    Text(AccountUsageService.subtitle(account: account, balanceMinor: balance))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .background(selected ? Theme.accent.opacity(0.16) : Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(selected ? Theme.accent : .primary)
        }
        .buttonStyle(.plain)
    }

    private var optionsRow: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                quickDateChip("今天", daysAgo: 0)
                quickDateChip("昨天", daysAgo: 1)
                quickDateChip("前天", daysAgo: 2)
                Spacer()
                DatePicker("日期", selection: $occurredAt, displayedComponents: .date)
                    .font(.caption)
                    .labelsHidden()
            }

            HStack(spacing: Theme.Spacing.m) {
                TextField("商家 / 对方（可选）", text: $payee)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                if selectedType == .expense {
                    Toggle("可报销", isOn: $isReimbursable)
                        .font(.caption)
                        .toggleStyle(.switch)
                        .fixedSize()
                }
            }

            HStack(spacing: Theme.Spacing.s) {
                Text("备注")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("可选", text: $note)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
    }

    /// 快捷日期：今天 / 昨天 / 前天
    private func quickDateChip(_ title: String, daysAgo: Int) -> some View {
        let target = quickDate(daysAgo)
        let selected = AppCalendar.isSameDay(occurredAt, target)
        return Button {
            occurredAt = target
            Haptics.selection()
        } label: {
            Text(title)
                .font(.caption2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Theme.accent.opacity(0.16) : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(selected ? Theme.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func quickDate(_ daysAgo: Int) -> Date {
        AppCalendar.gregorian.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            NumberPad { key in
                appendKey(key)
            }
            Button(action: save) {
                Text(canSave ? "保存 \(Money.format(amountMinor))" : "保存")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSave ? Theme.accent : Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .foregroundStyle(.white)
            }
            .disabled(!canSave)
            .padding(.horizontal, Theme.Spacing.l)
        }
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.l)
        .background(.regularMaterial)
    }

    // MARK: - 常用组合

    private var activeTemplates: [QuickTemplate] {
        templates
            .filter { $0.deletedAt == nil && bookMatches($0.bookId) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var templateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(activeTemplates, id: \.id) { template in
                    Button {
                        applyTemplate(template)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text(template.name)
                                .font(.caption2)
                                .lineLimit(1)
                            if let amount = template.amountMinor, amount > 0 {
                                Text(Money.format(amount))
                                    .font(.caption2.weight(.medium))
                                    .monospacedDigit()
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.10), in: Capsule())
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func applyTemplate(_ template: QuickTemplate) {
        guard let selection = QuickTemplateService.selection(from: template, accounts: accounts, categories: categories) else { return }

        if selection.type == .transfer {
            selectedType = .transfer
            if let accountId = selection.accountId,
               filteredAccounts.contains(where: { $0.id == accountId }) {
                selectedAccountId = accountId
            }
            Haptics.selection()
            return
        }

        selectedType = selection.type
        if let amount = selection.amountMinor {
            amountText = Money.rawText(amount)
        }
        if let accountId = selection.accountId,
           filteredAccounts.contains(where: { $0.id == accountId }) {
            selectedAccountId = accountId
        }
        if let categoryId = selection.categoryId,
           filteredCategories.contains(where: { $0.id == categoryId }) {
            selectedCategoryId = categoryId
        }
        payee = selection.payee ?? ""
        note = selection.note ?? ""
        Haptics.selection()
    }

    private func defaultTemplateName() -> String {
        var parts: [String] = []
        if let category = filteredCategories.first(where: { $0.id == selectedCategoryId }) {
            parts.append(category.name)
        } else if selectedType == .transfer {
            parts.append("转账")
        }
        if !payee.isEmpty { parts.append(payee) }
        if parts.isEmpty, let account = filteredAccounts.first(where: { $0.id == selectedAccountId }) {
            parts.append(account.name)
        }
        return parts.isEmpty ? "常用组合" : parts.joined(separator: " · ")
    }

    private func saveAsTemplate() {
        let trimmed = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? defaultTemplateName() : trimmed
        let nextOrder = ((templates.map { $0.sortOrder }.max()) ?? 0) + 1
        let template = QuickTemplate(
            bookId: currentBookId ?? books.first?.id ?? UUID(),
            name: name,
            type: selectedType,
            amountMinor: amountMinor > 0 ? amountMinor : nil,
            accountId: selectedAccountId,
            categoryId: selectedType == .transfer ? nil : selectedCategoryId,
            payee: payee.isEmpty ? nil : payee,
            note: note.isEmpty ? nil : note,
            sortOrder: nextOrder
        )
        context.insert(template)
        try? context.save()
        Haptics.success()
        templateName = ""
    }

    // MARK: - 逻辑

    private func prepareDefaults() {
        if selectedAccountId == nil, let detected = detectedMatchedAccount {
            selectedAccountId = detected.id
        }
        if selectedAccountId == nil {
            // 优先复用上次用的账户，其次第一个
            if let raw = UserDefaults.standard.string(forKey: Self.lastAccountKey),
               let lastId = UUID(uuidString: raw),
               filteredAccounts.contains(where: { $0.id == lastId }) {
                selectedAccountId = lastId
            } else {
                selectedAccountId = filteredAccounts.first?.id
            }
        }
        if let current = selectedAccountId, !filteredAccounts.contains(where: { $0.id == current }) {
            selectedAccountId = filteredAccounts.first?.id
        }
        if selectedCategoryId == nil && selectedType != .transfer {
            // 优先复用上次记账用过的分类
            if let raw = UserDefaults.standard.string(forKey: Self.lastCategoryKey),
               let lastId = UUID(uuidString: raw),
               filteredCategories.contains(where: { $0.id == lastId }) {
                selectedCategoryId = lastId
            } else {
                selectedCategoryId = filteredCategories.first?.id
            }
        }
        if selectedType == .transfer && counterAccountId == nil {
            counterAccountId = transferTargets.first?.id
        }
    }

    private static let lastCategoryKey = "entry.lastCategoryId"
    private static let lastAccountKey = "entry.lastAccountId"

    private func appendKey(_ key: String) {
        if key == "C" {
            amountText = "0"
            Haptics.warning()
            return
        }
        if key == "⌫" {
            amountText = String(amountText.dropLast())
            if amountText.isEmpty { amountText = "0" }
            return
        }
        if key == "." {
            if amountText.contains(".") { return }
            amountText += "."
            return
        }
        if amountText == "0" {
            amountText = key
        } else {
            amountText += key
        }
        Haptics.tap()
    }

    private func save() {
        guard amountMinor > 0 else { return }
        guard let accountId = selectedAccountId ?? filteredAccounts.first?.id else { return }
        let bookId = currentBookId ?? books.first?.id ?? UUID()

        if selectedType == .transfer {
            guard let targetId = counterAccountId, targetId != accountId else { return }
        }

        if let txn = editingTxn {
            txn.type = selectedType
            txn.amountMinor = amountMinor
            txn.accountId = accountId
            txn.counterAccountId = selectedType == .transfer ? counterAccountId : nil
            txn.categoryId = selectedType == .transfer ? nil : selectedCategoryId
            txn.note = note.isEmpty ? nil : note
            txn.payee = payee.isEmpty ? nil : payee
            txn.occurredAt = occurredAt
            applyReimbursable(to: txn, bookId: bookId)
            txn.updatedAt = Date()
        } else {
            let txn = Txn(
                bookId: bookId,
                type: selectedType,
                amountMinor: amountMinor,
                accountId: accountId,
                occurredAt: occurredAt,
                categoryId: selectedType == .transfer ? nil : selectedCategoryId,
                counterAccountId: selectedType == .transfer ? counterAccountId : nil,
                payee: payee.isEmpty ? nil : payee,
                note: note.isEmpty ? nil : note
            )
            context.insert(txn)
            applyReimbursable(to: txn, bookId: bookId)
        }

        try? context.save()
        refreshBalances()

        // 转账到信用卡 = 还款：自动按最早到期核销已登记账单
        if editingTxn == nil, selectedType == .transfer, let targetId = counterAccountId,
           let card = accounts.first(where: { $0.id == targetId }), card.type.isCreditLike {
            _ = StatementSettlementService.apply(
                paymentMinor: amountMinor,
                statements: statements.filter { $0.accountId == card.id }
            )
            try? context.save()
        }

        Haptics.success()

        if let categoryId = selectedCategoryId {
            UserDefaults.standard.set(categoryId.uuidString, forKey: Self.lastCategoryKey)
        }
        UserDefaults.standard.set(accountId.uuidString, forKey: Self.lastAccountKey)

        let categoryName = filteredCategories.first { $0.id == selectedCategoryId }?.name ?? "已记录"
        onSaved?("\(categoryName) \(Money.format(amountMinor))")

        dismiss()
    }

    /// 勾了「可报销」就挂到当月草稿报销单，没有就新建
    private func applyReimbursable(to txn: Txn, bookId: UUID) {
        guard selectedType == .expense, isReimbursable else {
            txn.isReimbursable = false
            txn.claimId = nil
            return
        }
        txn.isReimbursable = true
        if txn.claimId == nil {
            txn.claimId = draftClaimId(bookId: bookId)
        }
    }

    private func draftClaimId(bookId: UUID) -> UUID {
        let monthKey = AppCalendar.monthKey(occurredAt)
        if let existing = claims.first(where: {
            $0.deletedAt == nil && $0.status == .draft && $0.periodMonth == monthKey
        }) {
            return existing.id
        }
        let claim = Claim(bookId: bookId, title: "\(monthKey) 报销", periodMonth: monthKey)
        context.insert(claim)
        return claim.id
    }

    private func refreshBalances() {
        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        try? context.save()
    }

    // MARK: - 截图识别

    private func recognize(_ item: PhotosPickerItem) async {
        isRecognizing = true
        ocrHint = nil
        defer {
            isRecognizing = false
            photoItem = nil
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            ocrHint = "读取图片失败"
            return
        }

        let lines: [OCRLine] = await withCheckedContinuation { continuation in
            OCRService.recognize(image) { continuation.resume(returning: $0) }
        }

        let parsed = ScreenshotParser.parse(lines: lines)
        if let amount = parsed.amountMinor {
            amountText = Money.rawText(amount)
        }
        if let parsedPayee = parsed.payee, payee.isEmpty {
            payee = parsedPayee
        }

        if parsed.amountMinor == nil {
            ocrHint = "没识别出金额，请手动输入"
        } else if parsed.confidence < 0.6 {
            ocrHint = "识别置信度较低，请核对金额"
        } else {
            ocrHint = "已识别：\(Money.format(parsed.amountMinor ?? 0))"
            Haptics.success()
        }
    }
}

/// 简洁数字键盘
struct NumberPad: View {
    let onKey: (String) -> Void

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            onKey(key)
                        } label: {
                            Text(key)
                                .font(Theme.Fonts.amount(22, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .onLongPressGesture(minimumDuration: 0.6) {
                            if key == "⌫" { onKey("C") }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }
}
