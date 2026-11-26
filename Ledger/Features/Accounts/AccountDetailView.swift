import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let account: Account

    @Environment(\.modelContext) private var context
    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var categories: [Category]

    @State private var actualBalanceText = ""
    @State private var showCreditEditor = false
    @State private var showEdit = false
    @State private var showStatementEntry = false
    @State private var repayingStatement: Statement?
    @State private var reconcileMessage: String?

    @Query private var statements: [Statement]

    /// 未结清的账单：跨月也算，否则上月没还的账单在详情里会「消失」
    private var activeStatement: Statement? {
        statements
            .filter { $0.accountId == account.id && $0.deletedAt == nil && !$0.isSettled }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

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

    private var billInfo: CreditCardBillInfo? {
        CreditCardBillService.info(
            for: account,
            txns: allTxns.filter { $0.deletedAt == nil },
            statements: statements
        )
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
            ToolbarItem(placement: .topBarLeading) {
                Button("编辑") { showEdit = true }
            }
            if account.type.isCreditLike {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("账单设置") { showCreditEditor = true }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AccountEditView(account: account)
        }
        .sheet(isPresented: $showCreditEditor) {
            CreditCardSettingsSheet(account: account)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showStatementEntry) {
            StatementEntrySheet(
                account: account,
                suggestedAmount: billInfo?.estimatedAmountMinor ?? 0,
                suggestedPeriodMonth: billInfo?.periodMonth,
                suggestedDueDate: billInfo?.dueDate
            )
                .presentationDetents([.medium])
        }
        .sheet(item: $repayingStatement) { statement in
            StatementRepaySheet(account: account, statement: statement)
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(account.type.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Money.format(balance))
                .font(Theme.Fonts.amountXL)
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
            if let info = billInfo {
                LabeledContent("账单周期", value: periodText(info.statementPeriod))
                LabeledContent("出账日", value: DateFormatter.ledgerShort.string(from: info.billDate))
                LabeledContent("App 估算", value: Money.format(info.estimatedAmountMinor))

                if let statement = info.registered {
                    LabeledContent("已登记账单", value: Money.format(statement.billAmountMinor))
                    if statement.billAmountMinor != info.estimatedAmountMinor {
                        LabeledContent("与估算相差", value: signedDelta(statement.billAmountMinor - info.estimatedAmountMinor))
                            .foregroundStyle(Theme.warning)
                    }
                    LabeledContent("已还", value: Money.format(statement.paidAmountMinor))
                    LabeledContent("状态", value: statement.status.displayName)
                    if statement.minimumPaymentMinor > 0 {
                        LabeledContent(
                            "最低还款未还",
                            value: Money.format(max(0, statement.minimumPaymentMinor - statement.paidAmountMinor))
                        )
                    }
                    if statement.outstandingMinor > 0 {
                        Button("记还款") { repayingStatement = statement }
                    }
                } else {
                    LabeledContent("已出账账单", value: "未登记")
                    Button("按估算登记本期账单") { showStatementEntry = true }
                }

                LabeledContent("最后还款日", value: DateFormatter.ledgerShort.string(from: info.dueDate))
                let days = AppCalendar.gregorian.dateComponents(
                    [.day],
                    from: AppCalendar.startOfDay(for: Date()),
                    to: AppCalendar.startOfDay(for: info.dueDate)
                ).day ?? 0
                LabeledContent("剩余天数", value: days >= 0 ? "\(days) 天" : "已逾期 \(-days) 天")
                    .foregroundStyle(days < 0 ? Theme.danger : .primary)
            } else {
                Text("设置账单日与还款日后显示")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func periodText(_ period: DateInterval) -> String {
        let end = period.end.addingTimeInterval(-1)
        return "\(DateFormatter.ledgerShort.string(from: period.start)) – \(DateFormatter.ledgerShort.string(from: end))"
    }

    private func signedDelta(_ delta: Int64) -> String {
        let prefix = delta >= 0 ? "+" : "-"
        return prefix + Money.format(abs(delta))
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

struct CreditCardSettingsSheet: View {    let account: Account

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

// MARK: - 登记账单

struct StatementEntrySheet: View {
    let account: Account
    let suggestedAmount: Int64
    let suggestedPeriodMonth: String?
    let suggestedDueDate: Date?

    init(account: Account, suggestedAmount: Int64, suggestedPeriodMonth: String? = nil, suggestedDueDate: Date? = nil) {
        self.account = account
        self.suggestedAmount = suggestedAmount
        self.suggestedPeriodMonth = suggestedPeriodMonth
        self.suggestedDueDate = suggestedDueDate
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var minimumText = ""
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("账单金额（元）", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("最低还款（元，可留空）", text: $minimumText)
                        .keyboardType(.decimalPad)
                    DatePicker("最后还款日", selection: $dueDate, displayedComponents: .date)
                } footer: {
                    Text("填银行 App 里显示的「本期应还」。App 自己算的金额仅供参考，两者不一致时以银行为准。")
                }
            }
            .navigationTitle("登记本期账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled((Money.parse(amountText) ?? 0) <= 0)
                }
            }
            .onAppear {
                if amountText.isEmpty, suggestedAmount > 0 {
                    amountText = Money.rawText(suggestedAmount)
                }
                if let suggestedDueDate {
                    dueDate = suggestedDueDate
                } else if let billDay = account.billDay, let dueDay = account.dueDay {
                    let cycle = CreditCardCycle(billDay: billDay, dueDay: dueDay)
                    dueDate = cycle.dueDate(reference: Date()) ?? Date()
                }
            }
        }
    }

    private func save() {
        guard let amount = Money.parse(amountText) else { return }
        let statement = Statement(
            accountId: account.id,
            periodMonth: suggestedPeriodMonth ?? AppCalendar.monthKey(Date()),
            billAmountMinor: amount,
            minimumPaymentMinor: Money.parse(minimumText) ?? 0,
            dueDate: dueDate
        )
        statement.refreshStatus()
        context.insert(statement)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - 还款核销

struct StatementRepaySheet: View {
    let account: Account
    let statement: Statement

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Query private var statements: [Statement]

    @State private var amountText = ""
    @State private var paymentAccountId: UUID?

    private var paymentAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem && $0.id != account.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("还款金额") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                    Text("本期待还 \(Money.format(statement.outstandingMinor))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Picker("付款账户", selection: $paymentAccountId) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(paymentAccounts, id: \.id) { item in
                            Text(item.name).tag(UUID?.some(item.id))
                        }
                    }
                } header: {
                    Text("从哪个账户还款")
                } footer: {
                    Text("会生成一笔「转账」：付款账户 → 信用卡。信用卡还款不算支出，不会影响你的消费统计。")
                }
            }
            .navigationTitle("记还款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { repay() }
                        .disabled(paymentAccountId == nil || (Money.parse(amountText) ?? 0) <= 0)
                }
            }
            .onAppear {
                if amountText.isEmpty {
                    amountText = Money.rawText(statement.outstandingMinor)
                }
                if paymentAccountId == nil {
                    paymentAccountId = paymentAccounts.first?.id
                }
            }
        }
    }

    private func repay() {
        guard let accountId = paymentAccountId, let amount = Money.parse(amountText), amount > 0 else { return }

        let transfer = Txn(
            bookId: account.bookId,
            type: .transfer,
            amountMinor: amount,
            accountId: accountId,
            counterAccountId: account.id,
            note: "信用卡还款 · \(account.name)"
        )
        context.insert(transfer)

        // 一笔还款可能覆盖多期账单：按最早到期优先自动分摊
        _ = StatementSettlementService.apply(
            paymentMinor: amount,
            statements: statements.filter { $0.accountId == account.id }
        )
        try? context.save()

        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        BalanceService.refreshAll(accounts: allAccounts, transactions: all)
        try? context.save()

        Haptics.success()
        dismiss()
    }
}
