import SwiftUI
import SwiftData

struct LoanDetailView: View {
    let loan: Loan

    @Environment(\.modelContext) private var context
    @Query private var allItems: [LoanScheduleItem]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var showPrepay = false
    @State private var prepayText = ""
    @State private var strategy: PrepayStrategy = .shortenTerm

    private var items: [LoanScheduleItem] {
        allItems
            .filter { $0.loanId == loan.id && $0.deletedAt == nil }
            .sorted { $0.periodIndex < $1.periodIndex }
    }

    private var unpaidItems: [LoanScheduleItem] {
        items.filter { !$0.isPaid }
    }

    private var nextItem: LoanScheduleItem? {
        unpaidItems.first
    }

    private var paidCount: Int {
        items.filter { $0.isPaid }.count
    }

    private var liabilityAccount: Account? {
        accounts.first { $0.linkedLoanId == loan.id }
    }

    private var paymentAccount: Account? {
        accounts.first { $0.id == loan.paymentAccountId }
    }

    var body: some View {
        List {
            Section {
                header
            }

            if let next = nextItem {
                Section("下一期") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateFormatter.ledgerDateTime.string(from: next.dueDate))
                                .font(.subheadline)
                            Text("本金 \(Money.format(next.principalMinor)) · 利息 \(Money.format(next.interestMinor))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.format(next.totalMinor))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                    Button {
                        repay(next)
                    } label: {
                        Text("记本期还款")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if !items.isEmpty {
                Section {
                    Text("已全部还清 🎉")
                        .foregroundStyle(Theme.income)
                }
            }

            Section("还款计划（\(paidCount)/\(items.count) 期）") {
                ForEach(items.prefix(24), id: \.id) { item in
                    HStack {
                        Text("\(item.periodIndex)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateFormatter.ledgerShort.string(from: item.dueDate))
                                .font(.subheadline)
                            Text("本金 \(Money.format(item.principalMinor))  利息 \(Money.format(item.interestMinor))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.isPaid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.income)
                        } else {
                            Text(Money.format(item.totalMinor))
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
                if items.count > 24 {
                    Text("仅显示前 24 期，共 \(items.count) 期")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("提前还款") {
                    prepayText = ""
                    showPrepay = true
                }
                .disabled(unpaidItems.isEmpty)
            }
        }
        .navigationTitle(loan.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPrepay) {
            prepaySheet
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("剩余本金")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Money.format(loan.outstandingPrincipalMinor))
                .font(Theme.Fonts.amountXL)
                .monospacedDigit()
            HStack(spacing: Theme.Spacing.l) {
                infoItem("年利率", String(format: "%.2f%%", loan.annualRatePercent))
                infoItem("还款方式", loan.repaymentMethod.displayName)
                infoItem("剩余期数", "\(unpaidItems.count)")
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private func infoItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium))
        }
    }

    // MARK: - 记还款

    private func repay(_ item: LoanScheduleItem) {
        let bookId = loan.bookId

        // 本金：转账（扣款账户 → 贷款负债账户），不进支出
        if let liability = liabilityAccount, item.principalMinor > 0 {
            let transfer = Txn(
                bookId: bookId,
                type: .transfer,
                amountMinor: item.principalMinor,
                accountId: loan.paymentAccountId,
                counterAccountId: liability.id,
                note: "还款 · \(loan.name) 第\(item.periodIndex)期"
            )
            transfer.loanId = loan.id
            transfer.loanScheduleItemId = item.id
            context.insert(transfer)
            item.paymentTxnId = transfer.id
        }

        // 利息与手续费：支出
        let cost = item.interestMinor + item.feeMinor
        if cost > 0 {
            let interestCategory = categories.first { $0.name == "利息支出" && $0.kind == .expense }
            let expense = Txn(
                bookId: bookId,
                type: .expense,
                amountMinor: cost,
                accountId: loan.paymentAccountId,
                categoryId: interestCategory?.id,
                note: "利息 · \(loan.name) 第\(item.periodIndex)期"
            )
            expense.loanId = loan.id
            expense.loanScheduleItemId = item.id
            expense.interestMinor = cost
            context.insert(expense)
            item.interestTxnId = expense.id
        }

        item.isPaid = true
        item.paidAt = Date()
        item.paidAmountMinor = item.totalMinor
        item.updatedAt = Date()

        loan.outstandingPrincipalMinor = max(0, loan.outstandingPrincipalMinor - item.principalMinor)
        loan.updatedAt = Date()
        if unpaidItems.filter({ !$0.isPaid }).isEmpty {
            loan.status = .paidOff
        }

        try? context.save()
        refreshBalances()
        Haptics.success()
    }

    private func refreshBalances() {
        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        try? context.save()
    }

    // MARK: - 提前还款

    private var prepayMinor: Int64 {
        Money.parse(prepayText) ?? 0
    }

    private var prepayPreview: (schedule: [ScheduledPayment], saved: Int64) {
        guard prepayMinor > 0, let next = nextItem else { return ([], 0) }
        let outstandingAfter = max(0, loan.outstandingPrincipalMinor - prepayMinor)
        guard outstandingAfter > 0 else { return ([], 0) }

        let upcoming = unpaidItems.map {
            ScheduledPayment(
                periodIndex: $0.periodIndex,
                dueDate: $0.dueDate,
                principalMinor: $0.principalMinor,
                interestMinor: $0.interestMinor,
                feeMinor: $0.feeMinor
            )
        }

        let updated = LoanCalculator.reschedule(
            outstandingMinor: outstandingAfter,
            annualRateBp: loan.annualRateBp,
            remainingMonths: max(1, upcoming.count),
            originalMonthlyPaymentMinor: next.totalMinor,
            method: loan.repaymentMethod,
            firstDueDate: next.dueDate,
            strategy: strategy
        )
        return (updated, LoanCalculator.savedInterest(original: upcoming, updated: updated))
    }

    private var prepaySheet: some View {
        NavigationStack {
            Form {
                Section("提前还款金额") {
                    TextField("0.00", text: $prepayText)
                        .keyboardType(.decimalPad)
                    Text("当前剩余本金 \(Money.format(loan.outstandingPrincipalMinor))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("处理方式") {
                    Picker("方式", selection: $strategy) {
                        ForEach(PrepayStrategy.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if prepayMinor > 0, !prepayPreview.schedule.isEmpty {
                    Section("测算结果") {
                        LabeledContent("可省利息", value: Money.format(prepayPreview.saved))
                        LabeledContent("新剩余期数", value: "\(prepayPreview.schedule.count) 期")
                        LabeledContent("新月供", value: Money.format(prepayPreview.schedule.first?.totalMinor ?? 0))
                    }
                }
            }
            .navigationTitle("提前还款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showPrepay = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { prepay() }
                        .disabled(prepayMinor <= 0)
                }
            }
        }
    }

    private func prepay() {
        guard prepayMinor > 0, let next = nextItem else { return }

        // 先快照未还期次，再删除，否则重排时拿不到原始数据
        let upcomingSnapshot = unpaidItems.map {
            ScheduledPayment(
                periodIndex: $0.periodIndex,
                dueDate: $0.dueDate,
                principalMinor: $0.principalMinor,
                interestMinor: $0.interestMinor,
                feeMinor: $0.feeMinor
            )
        }

        // 本金部分：转账
        if let liability = liabilityAccount {
            let transfer = Txn(
                bookId: loan.bookId,
                type: .transfer,
                amountMinor: prepayMinor,
                accountId: loan.paymentAccountId,
                counterAccountId: liability.id,
                note: "提前还款 · \(loan.name)"
            )
            transfer.loanId = loan.id
            context.insert(transfer)
        }

        loan.outstandingPrincipalMinor = max(0, loan.outstandingPrincipalMinor - prepayMinor)

        // 删掉未还期次，按新本金重排
        for item in unpaidItems {
            context.delete(item)
        }

        if loan.outstandingPrincipalMinor == 0 {
            loan.status = .paidOff
        } else {
            let updated = LoanCalculator.reschedule(
                outstandingMinor: loan.outstandingPrincipalMinor,
                annualRateBp: loan.annualRateBp,
                remainingMonths: max(1, upcomingSnapshot.count),
                originalMonthlyPaymentMinor: next.totalMinor,
                method: loan.repaymentMethod,
                firstDueDate: next.dueDate,
                strategy: strategy
            )
            for (index, scheduled) in updated.enumerated() {
                let item = LoanScheduleItem(
                    loanId: loan.id,
                    periodIndex: index + 1,
                    dueDate: scheduled.dueDate,
                    principalMinor: scheduled.principalMinor,
                    interestMinor: scheduled.interestMinor,
                    feeMinor: scheduled.feeMinor
                )
                context.insert(item)
            }
        }

        try? context.save()
        refreshBalances()
        Haptics.success()
        showPrepay = false
    }
}
