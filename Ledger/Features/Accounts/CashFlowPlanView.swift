import SwiftUI
import SwiftData

/// 资金计划：未来 30/60/90 天的已知流出流入时间线。
struct CashFlowPlanView: View {
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var allTxns: [Txn]
    @Query private var loans: [Loan]
    @Query private var scheduleItems: [LoanScheduleItem]
    @Query private var recurringRules: [RecurringRule]
    @Query private var debts: [Debt]
    @Query private var statements: [Statement]

    @State private var days = 30

    private var plan: CashFlowPlan {
        CashFlowForecast.plan(
            days: days,
            accounts: accounts,
            transactions: allTxns,
            loans: loans,
            loanScheduleItems: scheduleItems,
            recurringRules: recurringRules,
            debts: debts,
            statements: statements
        )
    }

    private var groupedEvents: [(day: Date, events: [CashFlowEvent])] {
        let calendar = AppCalendar.gregorian
        let grouped = Dictionary(grouping: plan.events) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            (day, (grouped[day] ?? []).sorted { $0.title < $1.title })
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("当前可用资金")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Money.format(plan.startingBalanceMinor))
                        .font(Theme.Fonts.amountXL)
                        .monospacedDigit()
                        .foregroundStyle(plan.startingBalanceMinor < 0 ? Theme.danger : .primary)

                    HStack(spacing: Theme.Spacing.xl) {
                        metric("未来 \(days) 天流出", Money.format(plan.outflowMinor), Theme.warning)
                        metric("流入", Money.format(plan.inflowMinor), Theme.income)
                        metric("期末预计", Money.format(plan.endingBalanceMinor), plan.endingBalanceMinor < 0 ? Theme.danger : .primary)
                    }
                }
                .padding(.vertical, Theme.Spacing.s)

                Picker("范围", selection: $days) {
                    Text("30 天").tag(30)
                    Text("60 天").tag(60)
                    Text("90 天").tag(90)
                }
                .pickerStyle(.segmented)
            }

            if groupedEvents.isEmpty {
                Section {
                    Text("未来 \(days) 天没有已知的还款或周期支出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groupedEvents, id: \.day) { group in
                    Section {
                        ForEach(group.events) { event in
                            row(event)
                        }
                    } header: {
                        HStack {
                            Text(dayLabel(group.day))
                            Spacer()
                            Text(dayTotal(group.events))
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
            } footer: {
                Text("口径：现金/储蓄卡/电子钱包/储值卡的余额计入可用资金；信用卡已登记未结清账单用真实金额，未登记的按最近一个完整账单周期消费估算；贷款、周期记账、有到期日的借入借出都按计划日期计入。")
            }
        }
        .navigationTitle("资金计划")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.Fonts.amountS)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func row(_ event: CashFlowEvent) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: event.kind.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(event.amountMinor >= 0 ? Theme.income : Theme.warning)
                .frame(width: 26, height: 26)
                .background(
                    (event.amountMinor >= 0 ? Theme.income : Theme.warning).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(event.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(amountText(event.amountMinor))
                .font(Theme.Fonts.amountM)
                .monospacedDigit()
                .foregroundStyle(event.amountMinor >= 0 ? Theme.income : .primary)
        }
        .padding(.vertical, 2)
    }

    private func amountText(_ amount: Int64) -> String {
        let prefix = amount >= 0 ? "+" : "-"
        return prefix + Money.format(abs(amount))
    }

    private func dayTotal(_ events: [CashFlowEvent]) -> String {
        let total = events.reduce(Int64(0)) { $0 + $1.amountMinor }
        return amountText(total)
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = AppCalendar.gregorian
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInTomorrow(date) { return "明天" }
        return DateFormatter.ledgerShort.string(from: date)
    }
}
