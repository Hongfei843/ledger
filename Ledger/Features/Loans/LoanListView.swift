import SwiftUI
import SwiftData

struct LoanListView: View {
    @Environment(\.modelContext) private var context
    @Query private var loans: [Loan]
    @Query private var items: [LoanScheduleItem]
    @Query private var accounts: [Account]
    @Query private var books: [Book]

    @State private var showNew = false

    private var activeLoans: [Loan] {
        loans.filter { $0.deletedAt == nil && $0.status != .archived }
    }

    private var liveItems: [LoanScheduleItem] {
        items.filter { $0.deletedAt == nil }
    }

    private var totalDebtMinor: Int64 {
        activeLoans.filter { $0.status == .active }.reduce(Int64(0)) { $0 + $1.outstandingPrincipalMinor }
    }

    private var monthDueMinor: Int64 {
        let interval = AppCalendar.monthInterval(containing: Date())
        return liveItems
            .filter { !$0.isPaid && interval.contains($0.dueDate) }
            .reduce(Int64(0)) { $0 + $1.totalMinor }
    }

    private var yearInterestMinor: Int64 {
        let year = AppCalendar.gregorian.component(.year, from: Date())
        return liveItems
            .filter { item in
                guard item.isPaid, let paidAt = item.paidAt else { return false }
                return AppCalendar.gregorian.component(.year, from: paidAt) == year
            }
            .reduce(Int64(0)) { $0 + $1.interestMinor + $1.feeMinor }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCard
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("贷款") {
                    if activeLoans.isEmpty {
                        Text("还没有贷款记录")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(activeLoans, id: \.id) { loan in
                        NavigationLink {
                            LoanDetailView(loan: loan)
                        } label: {
                            loanRow(loan)
                        }
                    }
                }
            }
            .navigationTitle("负债")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew) {
                NewLoanSheet()
                    .presentationDetents([.large])
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("总负债").font(.caption2).foregroundStyle(.secondary)
                Text(Money.format(totalDebtMinor))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("本月应还").font(.caption2).foregroundStyle(.secondary)
                Text(Money.format(monthDueMinor))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text("今年利息 \(Money.format(yearInterestMinor))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func loanRow(_ loan: Loan) -> some View {
        let loanItems = liveItems.filter { $0.loanId == loan.id }
        let paid = loanItems.filter { $0.isPaid }.count
        let total = max(1, loanItems.count)
        let next = loanItems.filter { !$0.isPaid }.sorted { $0.dueDate < $1.dueDate }.first

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(loan.name).font(.subheadline.weight(.medium))
                Spacer()
                Text(loan.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("剩余 \(Money.format(loan.outstandingPrincipalMinor))")
                    .font(.caption)
                    .monospacedDigit()
                Spacer()
                Text("年利率 \(String(format: "%.2f%%", loan.annualRatePercent))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(paid), total: Double(total))
                .tint(Theme.accent)
            if let next {
                HStack {
                    Text("\(paid)/\(total) 期")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("下期 \(DateFormatter.ledgerShort.string(from: next.dueDate)) · \(Money.format(next.totalMinor))")
                        .font(.caption2)
                        .foregroundStyle(next.isPaid ? .secondary : Theme.warning)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct NewLoanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query private var books: [Book]

    @State private var name = ""
    @State private var type: LoanType = .mortgageProvident
    @State private var method: RepaymentMethod = .equalInstallment
    @State private var principalText = ""
    @State private var rateText = "3.1"
    @State private var termText = "360"
    @State private var firstDueDate = Date()
    @State private var paymentAccountId: UUID?

    private var paymentAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
    }

    private var previewItems: [ScheduledPayment] {
        guard let principal = Money.parse(principalText), principal > 0,
              let rate = Double(rateText),
              let term = Int(termText), term > 0 else {
            return []
        }
        return LoanCalculator.schedule(
            principalMinor: principal,
            annualRateBp: Int((rate * 100).rounded()),
            termMonths: term,
            method: method,
            firstDueDate: firstDueDate
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称，如 公积金房贷", text: $name)
                    Picker("类型", selection: $type) {
                        ForEach(LoanType.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .onChange(of: type) { _, newValue in
                        method = defaultMethod(for: newValue)
                    }
                }

                Section("金额与利率") {
                    TextField("本金（元）", text: $principalText)
                        .keyboardType(.decimalPad)
                    TextField("年利率（%）", text: $rateText)
                        .keyboardType(.decimalPad)
                    TextField("期数（月）", text: $termText)
                        .keyboardType(.numberPad)
                }

                Section("还款") {
                    Picker("方式", selection: $method) {
                        ForEach(RepaymentMethod.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    DatePicker("首次还款日", selection: $firstDueDate, displayedComponents: .date)
                    Picker("还款账户", selection: $paymentAccountId) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(paymentAccounts, id: \.id) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }

                if let first = previewItems.first {
                    Section("还款计划预览") {
                        LabeledContent("每期还款", value: Money.format(first.totalMinor))
                        LabeledContent("期数", value: "\(previewItems.count)")
                        LabeledContent("利息合计", value: Money.format(LoanCalculator.totalInterest(previewItems)))
                    }
                }
            }
            .navigationTitle("新建贷款")
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
            .onAppear {
                if paymentAccountId == nil { paymentAccountId = paymentAccounts.first?.id }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (Money.parse(principalText) ?? 0) > 0
            && paymentAccountId != nil
            && !previewItems.isEmpty
    }

    private func defaultMethod(for type: LoanType) -> RepaymentMethod {
        switch type {
        case .consumerInstallment, .carLoan:
            return .interestOnly
        case .creditCardInstallment:
            return .installmentFee
        default:
            return .equalInstallment
        }
    }

    private func save() {
        guard let principal = Money.parse(principalText),
              let rate = Double(rateText),
              let term = Int(termText),
              let accountId = paymentAccountId,
              let bookId = books.first?.id else { return }

        let loan = Loan(
            bookId: bookId,
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            principalMinor: principal,
            annualRateBp: Int((rate * 100).rounded()),
            termMonths: term,
            startDate: Date(),
            firstDueDate: firstDueDate,
            dueDay: AppCalendar.gregorian.component(.day, from: firstDueDate),
            repaymentMethod: method,
            paymentAccountId: accountId
        )
        if type == .mortgageProvident {
            loan.providentMode = .monthlyOffset
        }
        context.insert(loan)

        // 系统负债账户：余额为负，随还款逐步回到 0
        let liability = Account(
            bookId: bookId,
            name: loan.name,
            type: .loan,
            openingBalanceMinor: -principal,
            iconEmoji: "🏦",
            colorHex: "C2410C",
            sortOrder: 100
        )
        liability.isSystem = true
        liability.linkedLoanId = loan.id
        context.insert(liability)

        for item in previewItems {
            let scheduleItem = LoanScheduleItem(
                loanId: loan.id,
                periodIndex: item.periodIndex,
                dueDate: item.dueDate,
                principalMinor: item.principalMinor,
                interestMinor: item.interestMinor,
                feeMinor: item.feeMinor
            )
            context.insert(scheduleItem)
        }

        try? context.save()
        Haptics.success()
        dismiss()
    }
}
