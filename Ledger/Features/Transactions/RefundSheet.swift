import SwiftUI
import SwiftData

/// 给已有支出补记一笔退款：生成 income 流水并挂到原支出上，统计时冲减支出、不算收入。
struct RefundSheet: View {
    let original: Txn
    /// 原支出已退款合计（由详情页传入，避免这里再扫全表）
    let alreadyRefundedMinor: Int64

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var amountText: String
    @State private var accountId: UUID?
    @State private var occurredAt = Date()
    @State private var note = ""

    init(original: Txn, alreadyRefundedMinor: Int64) {
        self.original = original
        self.alreadyRefundedMinor = alreadyRefundedMinor
        let remaining = max(0, original.amountMinor - alreadyRefundedMinor)
        _amountText = State(initialValue: Money.rawText(remaining))
        _accountId = State(initialValue: original.accountId)
    }

    private var remainingMinor: Int64 { max(0, original.amountMinor - alreadyRefundedMinor) }
    private var amountMinor: Int64 { Money.parse(amountText) ?? 0 }
    private var canSave: Bool { amountMinor > 0 && amountMinor <= remainingMinor }

    private var activeAccounts: [Account] {
        accounts
            .filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var categoryName: String {
        categories.first { $0.id == original.categoryId }?.name ?? "原分类"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("退款金额", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(Theme.Fonts.amount(26))
                    HStack {
                        Text("可退剩余")
                        Spacer()
                        Text(Money.format(remainingMinor))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                } footer: {
                    Text("退款会生成一笔收入流水回到原账户，在统计里冲减「\(categoryName)」的支出，不会重复算成收入。")
                }

                Section("退回账户") {
                    Picker("退回账户", selection: $accountId) {
                        ForEach(activeAccounts, id: \.id) { account in
                            Text(account.displayName).tag(UUID?.some(account.id))
                        }
                    }
                }

                Section("时间") {
                    DatePicker("退款日期", selection: $occurredAt, displayedComponents: .date)
                }

                Section("备注") {
                    TextField("可选，如 部分退款", text: $note)
                }
            }
            .navigationTitle("记一笔退款")
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
        guard canSave else { return }
        let account = activeAccounts.first { $0.id == accountId }
            ?? activeAccounts.first { $0.id == original.accountId }
        guard let account else { return }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let txn = Txn(
            bookId: original.bookId,
            type: .income,
            amountMinor: amountMinor,
            accountId: account.id,
            occurredAt: occurredAt,
            categoryId: original.categoryId,
            note: trimmedNote.isEmpty ? "退款" : trimmedNote
        )
        txn.refundOfTxnId = original.id
        context.insert(txn)
        try? context.save()
        refreshBalances()
        Haptics.success()
        dismiss()
    }

    private func refreshBalances() {
        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        try? context.save()
    }
}
