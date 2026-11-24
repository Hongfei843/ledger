import SwiftUI
import SwiftData

private struct DayGroup: Identifiable {
    let id: Date
    let day: Date
    let items: [Txn]
    let expenseMinor: Int64
}

struct TransactionListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var showEntry = false

    private var activeTxns: [Txn] {
        allTxns.filter { $0.deletedAt == nil }
    }

    private var monthTxns: [Txn] {
        let interval = AppCalendar.monthInterval(containing: Date())
        return activeTxns.filter { interval.contains($0.occurredAt) }
    }

    private var monthExpense: Int64 {
        monthTxns.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var monthIncome: Int64 {
        monthTxns.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var groups: [DayGroup] {
        var buckets: [Date: [Txn]] = [:]
        for txn in activeTxns {
            let key = AppCalendar.startOfDay(txn.occurredAt)
            buckets[key, default: []].append(txn)
        }
        return buckets.keys.sorted(by: >).map { key in
            let items = buckets[key] ?? []
            let expense = items.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
            return DayGroup(id: key, day: key, items: items, expenseMinor: expense)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                List {
                    Section {
                        monthSummaryCard
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    if groups.isEmpty {
                        Section {
                            emptyState
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.items, id: \.id) { txn in
                                    NavigationLink {
                                        TxnDetailView(txn: txn)
                                    } label: {
                                        TxnRow(
                                            txn: txn,
                                            category: category(for: txn),
                                            accountName: accountName(for: txn)
                                        )
                                    }
                                }
                                .onDelete { offsets in
                                    delete(at: offsets, in: group)
                                }
                            } header: {
                                HStack {
                                    Text(AppCalendar.dayTitle(group.day))
                                    Spacer()
                                    if group.expenseMinor > 0 {
                                        Text("支出 \(Money.format(group.expenseMinor))")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)

                Button {
                    showEntry = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Theme.accent, in: Circle())
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                }
                .padding(.trailing, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .navigationTitle("明细")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showEntry) {
                EntrySheet()
                    .presentationDetents([.large])
            }
        }
    }

    private var monthSummaryCard: some View {
        HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("本月支出")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(Money.format(monthExpense))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: Theme.Spacing.s)
            summaryItem(title: "收入", value: Money.format(monthIncome), color: Theme.income)
            summaryItem(title: "结余", value: Money.format(monthIncome - monthExpense), color: .primary)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func summaryItem(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("还没有记录")
                .font(.headline)
            Text("点右下角的 + 记第一笔")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    private func category(for txn: Txn) -> Category? {
        categories.first { $0.id == txn.categoryId }
    }

    private func accountName(for txn: Txn) -> String {
        accounts.first { $0.id == txn.accountId }?.name ?? "—"
    }

    private func delete(at offsets: IndexSet, in group: DayGroup) {
        for index in offsets {
            let txn = group.items[index]
            txn.deletedAt = Date()
            txn.updatedAt = Date()
        }
        try? context.save()

        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        try? context.save()
        Haptics.warning()
    }
}

struct TxnRow: View {
    let txn: Txn
    let category: Category?
    let accountName: String

    private var amountColor: Color {
        switch txn.type {
        case .income: return Theme.income
        case .transfer: return Theme.transfer
        case .adjustment: return Theme.transfer
        default: return .primary
        }
    }

    private var amountPrefix: String {
        switch txn.type {
        case .income: return "+"
        case .transfer: return ""
        case .adjustment: return txn.amountMinor >= 0 ? "+" : "-"
        default: return "-"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            CategoryIconView(category: category, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(category?.name ?? txn.type.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(amountPrefix + Money.format(abs(txn.amountMinor)))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 2)
    }

    /// 副标题：备注 · 账户（备注为空时只显示账户）
    private var subtitle: String {
        var parts: [String] = []
        if let note = txn.note, !note.isEmpty {
            parts.append(note)
        }
        if let payee = txn.payee, !payee.isEmpty {
            parts.append(payee)
        }
        parts.append(accountName)
        return parts.joined(separator: " · ")
    }
}
