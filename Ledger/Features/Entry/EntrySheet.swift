import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct EntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var books: [Book]
    @Query private var claims: [Claim]
    @Query private var allTxns: [Txn]

    @State private var amountText = "0"
    @State private var selectedType: TxnType = .expense
    @State private var selectedCategoryId: UUID?
    @State private var selectedAccountId: UUID?
    @State private var counterAccountId: UUID?
    @State private var note = ""
    @State private var occurredAt = Date()
    @State private var isReimbursable = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isRecognizing = false
    @State private var ocrHint: String?

    /// 传入已有流水表示编辑模式
    private let editingTxn: Txn?

    init(editingTxn: Txn? = nil) {
        self.editingTxn = editingTxn
        _amountText = State(initialValue: editingTxn.map { Money.rawText($0.amountMinor) } ?? "0")
        _selectedType = State(initialValue: editingTxn?.type ?? .expense)
        _selectedCategoryId = State(initialValue: editingTxn?.categoryId)
        _selectedAccountId = State(initialValue: editingTxn?.accountId)
        _counterAccountId = State(initialValue: editingTxn?.counterAccountId)
        _note = State(initialValue: editingTxn?.note ?? "")
        _occurredAt = State(initialValue: editingTxn?.occurredAt ?? Date())
        _isReimbursable = State(initialValue: editingTxn?.isReimbursable ?? false)
    }

    // MARK: - 数据

    private var baseAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
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

    /// 每个分类的累计记账笔数，用于动态排序
    private var usageCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for txn in allTxns where txn.deletedAt == nil {
            guard let categoryId = txn.categoryId else { continue }
            counts[categoryId, default: 0] += 1
        }
        return counts
    }

    private var filteredCategories: [Category] {
        let kind: CategoryKind = selectedType == .income ? .income : .expense
        let counts = usageCounts
        return categories
            .filter { $0.deletedAt == nil && !$0.isArchived && $0.kind == kind }
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

                if selectedType == .transfer {
                    transferSection
                } else {
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
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await recognize(item) }
            }
            .onAppear(perform: prepareDefaults)
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
        .onChange(of: selectedType) { _, newValue in
            selectedCategoryId = filteredCategories.first?.id
            if newValue == .income, let current = selectedAccountId,
               !filteredAccounts.contains(where: { $0.id == current }) {
                selectedAccountId = filteredAccounts.first?.id
            }
            if newValue != .expense {
                isReimbursable = false
            }
        }
    }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Money.symbol)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(amountText)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
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

    private var categoryGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: Theme.Spacing.s) {
                ForEach(filteredCategories, id: \.id) { category in
                    categoryCell(category)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .frame(maxHeight: 280)
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

    private func accountChip(_ account: Account, selection: Binding<UUID?>) -> some View {
        let selected = selection.wrappedValue == account.id
        return Button {
            selection.wrappedValue = account.id
            Haptics.selection()
        } label: {
            HStack(spacing: 4) {
                Text(account.iconEmoji).font(.system(size: 13))
                Text(account.name).font(.caption)
                if account.type.isLiability {
                    Text("负债").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(selected ? Theme.accent.opacity(0.16) : Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(selected ? Theme.accent : .primary)
        }
        .buttonStyle(.plain)
    }

    private var optionsRow: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                DatePicker("日期", selection: $occurredAt, displayedComponents: .date)
                    .font(.caption)
                    .labelsHidden()
                Spacer()
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

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            NumberPad { key in
                appendKey(key)
            }
            Button(action: save) {
                Text("保存")
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

    // MARK: - 逻辑

    private func prepareDefaults() {
        if selectedAccountId == nil {
            selectedAccountId = filteredAccounts.first?.id
        }
        if selectedCategoryId == nil && selectedType != .transfer {
            selectedCategoryId = filteredCategories.first?.id
        }
        if selectedType == .transfer && counterAccountId == nil {
            counterAccountId = transferTargets.first?.id
        }
    }

    private func appendKey(_ key: String) {
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
        let bookId = books.first?.id ?? UUID()

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
                note: note.isEmpty ? nil : note
            )
            context.insert(txn)
            applyReimbursable(to: txn, bookId: bookId)
        }

        try? context.save()
        refreshBalances()
        Haptics.success()
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
        if let payee = parsed.payee, note.isEmpty {
            note = payee
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
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }
}
