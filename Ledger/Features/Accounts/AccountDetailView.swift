import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let account: Account

    @Environment(\.modelContext) private var context
    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var categories: [Category]

    @State private var actualBalanceText = ""
    @State private var showCreditEditor = false
    @State private var reconcileMessage: String?

    private var liveTxns: [Txn] {
        allTxns.filter { $0.deletedAt == nil && ($0.accountId == account.id || $0.counterAccountId == account.id) }
    }

    private var balance: Int64 {
        BalanceService.balance(
            of: account,
            transactions: allTxns.filter { $0.deletedAt == nil },
            openingBalanceMinor: account.openingBalanceMinor
        )
    }

    private var cycle: CreditCardCycle? {
        guard let billDay = account.billDay, let dueDay = account.dueDay, billDay > 0, dueDay > 0 else { return nil }
        return CreditCardCycle(billDay: billDay, dueDay: dueDay)
    }

    private var statementAmount: Int64? {
        guard let cycle, let period = cycle.statementPeriod(reference: Date()) else { return nil }
        return allTxns
            .filter { $0.deletedAt == nil && $0.accountId == account.id && $0.type == .expense && period.contains($0.occurredAt) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    var body: some View {
        List {
            Section {
                header
            }

            if account.type.isCreditLike {
                creditSection
            }

            Section {
                HStack {
                    TextField("输入实际余额", text: $actualBalanceText)
                        .keyboardType(.numbersAndPunctuation)
                    Button("校准") { reconcile() }
                        .disabled(Money.parse(actualBalanceText) == nil)
                }
                if let reconcileMessage {
                    Text(reconcileMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.income)
                }
            } header: {
                Text("余额校准")
            } footer: {
                Text("输入银行 App 里看到的实际余额，系统会生成一条「余额调整」把账面拉平，且不计入收支统计。")
            }

            Section("最近流水") {
                if liveTxns.isEmpty {
                    Text("暂无").foregroundStyle(.secondary)
                }
                ForEach(liveTxns.prefix(20), id: \.id) { txn in
                    NavigationLink {
                        TxnDetailView(txn: txn)
                    } label: {
                        HStack {
                            Text(categories.first { $0.id == txn.categoryId }?.iconEmoji ?? "📦")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(txn.note?.isEmpty == false ? (txn.note ?? "") : (categories.first { $0.id == txn.categoryId }?.name ?? txn.type.displayName))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(DateFormatter.ledgerShort.string(from: txn.occurredAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(abs(txn.amountMinor)))
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if account.type.isCreditLike {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("账单设置") { showCreditEditor = true }
                }
            }
        }
        .sheet(isPresented: $showCreditEditor) {
            CreditCardSettingsSheet(account: account)
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(account.type.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Money.format(balance))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(balance < 0 ? Theme.danger : .primary)
            if account.type.isCreditLike, let limit = account.creditLimitMinor {
                Text("可用额度 \(Money.format(limit + balance)) / \(Money.format(limit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private var creditSection: some View {
        Section("本期账单") {
            if let statementAmount {
                LabeledContent("账单金额", value: Money.format(statementAmount))
            }
            if let cycle, let due = cycle.dueDate(reference: Date()) {
                LabeledContent("最后还款日", value: DateFormatter.ledgerShort.string(from: due))
                if let days = cycle.daysUntilDue(reference: Date()) {
                    LabeledContent("剩余天数", value: days >= 0 ? "\(days) 天" : "已逾期 \(-days) 天")
                }
            } else {
                Text("设置账单日与还款日后显示")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reconcile() {
        guard let actual = Money.parse(actualBalanceText) else { return }
        let delta = actual - balance
        guard delta != 0 else {
            reconcileMessage = "账面与实际一致，无需调整"
            return
        }

        let txn = Txn(
            bookId: account.bookId,
            type: .adjustment,
            amountMinor: delta,
            accountId: account.id,
            note: "余额校准"
        )
        context.insert(txn)
        try? context.save()

        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        try? context.save()

        actualBalanceText = ""
        reconcileMessage = "已调整 \(Money.format(delta))"
        Haptics.success()
    }
}

struct CreditCardSettingsSheet: View {
    let account: Account

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var limitText = ""
    @State private var billDay = 1
    @State private var dueDay = 20

    var body: some View {
        NavigationStack {
            Form {
                Section("额度") {
                    TextField("信用额度（元）", text: $limitText)
                        .keyboardType(.decimalPad)
                }
                Section("账单周期") {
                    Stepper("账单日：每月 \(billDay) 日", value: $billDay, in: 1...28)
                    Stepper("还款日：每月 \(dueDay) 日", value: $dueDay, in: 1...28)
                }
            }
            .navigationTitle("账单设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear {
                if let limit = account.creditLimitMinor {
                    limitText = Money.rawText(limit)
                }
                billDay = account.billDay ?? 1
                dueDay = account.dueDay ?? 20
            }
        }
    }

    private func save() {
        account.creditLimitMinor = Money.parse(limitText)
        account.billDay = billDay
        account.dueDay = dueDay
        account.updatedAt = Date()
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
