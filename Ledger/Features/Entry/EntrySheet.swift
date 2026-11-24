import SwiftUI
import SwiftData

struct EntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var books: [Book]

    @State private var amountText = "0"
    @State private var selectedType: TxnType = .expense
    @State private var selectedCategoryId: UUID?
    @State private var selectedAccountId: UUID?
    @State private var note = ""

    private var filteredAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
    }

    private var filteredCategories: [Category] {
        let kind: CategoryKind = selectedType == .income ? .income : .expense
        return categories
            .filter { $0.deletedAt == nil && !$0.isArchived && $0.kind == kind }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var amountMinor: Int64 {
        Money.parse(amountText) ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                typePicker
                amountDisplay
                categoryGrid
                selectedRow
                Spacer(minLength: 0)
                bottomBar
            }
            .background(Theme.pageBackground)
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear(perform: prepareDefaults)
        }
    }

    // MARK: - 子视图

    private var typePicker: some View {
        Picker("类型", selection: $selectedType) {
            Text("支出").tag(TxnType.expense)
            Text("收入").tag(TxnType.income)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.m)
        .onChange(of: selectedType) { _, _ in
            selectedCategoryId = filteredCategories.first?.id
        }
    }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Money.symbol)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(amountText)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.l)
    }

    private var categoryGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: 5), spacing: Theme.Spacing.m) {
                ForEach(filteredCategories, id: \.id) { category in
                    categoryCell(category)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxHeight: 260)
    }

    private func categoryCell(_ category: Category) -> some View {
        let selected = selectedCategoryId == category.id
        return Button {
            selectedCategoryId = category.id
            Haptics.selection()
        } label: {
            VStack(spacing: 4) {
                Text(category.iconEmoji)
                    .font(.system(size: 22))
                    .frame(width: 46, height: 46)
                    .background(
                        selected
                        ? Theme.accent.opacity(0.18)
                        : Color(.secondarySystemBackground),
                        in: Circle()
                    )
                    .overlay(
                        Circle().stroke(selected ? Theme.accent : Color.clear, lineWidth: 2)
                    )
                Text(category.name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var selectedRow: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack {
                Text("账户")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(filteredAccounts, id: \.id) { account in
                        accountChip(account)
                    }
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
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.m)
    }

    private func accountChip(_ account: Account) -> some View {
        let selected = selectedAccountId == account.id
        return Button {
            selectedAccountId = account.id
            Haptics.selection()
        } label: {
            HStack(spacing: 4) {
                Text(account.iconEmoji).font(.system(size: 14))
                Text(account.name).font(.caption)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(
                selected ? Theme.accent.opacity(0.16) : Color(.secondarySystemBackground),
                in: Capsule()
            )
            .foregroundStyle(selected ? Theme.accent : .primary)
        }
        .buttonStyle(.plain)
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
                    .background(amountMinor > 0 ? Theme.accent : Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .foregroundStyle(.white)
            }
            .disabled(amountMinor <= 0)
            .padding(.horizontal, Theme.Spacing.xl)
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
        if selectedCategoryId == nil {
            selectedCategoryId = filteredCategories.first?.id
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
        guard let amount = Money.parse(amountText), amount > 0 else { return }
        guard let accountId = selectedAccountId ?? filteredAccounts.first?.id else { return }
        let bookId = books.first?.id ?? UUID()

        let txn = Txn(
            bookId: bookId,
            type: selectedType,
            amountMinor: amount,
            accountId: accountId,
            categoryId: selectedCategoryId,
            note: note.isEmpty ? nil : note
        )
        context.insert(txn)
        try? context.save()

        let descriptor = FetchDescriptor<Txn>()
        let all = (try? context.fetch(descriptor)) ?? []
        if let account = accounts.first(where: { $0.id == accountId }) {
            BalanceService.refresh(account: account, transactions: all)
            try? context.save()
        }

        Haptics.success()
        dismiss()
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
        .padding(.horizontal, Theme.Spacing.xl)
    }
}
