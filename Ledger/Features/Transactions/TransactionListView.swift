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
    @Query(
        filter: #Predicate<Txn> { $0.deletedAt == nil },
        sort: \Txn.occurredAt,
        order: .reverse
    ) private var allTxns: [Txn]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var showEntry = false
    @State private var period = PeriodRange()
    @State private var showCustomRange = false
    @State private var customStart = Date()
    @State private var customEnd = Date()

    private var activeTxns: [Txn] { allTxns }
    private var interval: DateInterval { period.interval() }

    private var periodTxns: [Txn] {
        activeTxns.filter { interval.contains($0.occurredAt) }
    }

    private var periodExpense: Int64 {
        periodTxns.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var periodIncome: Int64 {
        periodTxns.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var groups: [DayGroup] {
        var buckets: [Date: [Txn]] = [:]
        for txn in periodTxns {
            let key = AppCalendar.startOfDay(txn.occurredAt)
            buckets[key, default: []].append(txn)
        }
        return buckets.keys.sorted(by: >).map { key in
            let items = buckets[key] ?? []
            let expense = items.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
            return DayGroup(id: key, day: key, items: items, expenseMinor: expense)
        }
    }

    /// 超过 30 天没对账、且确实有钱进出的账户
    private var staleAccounts: [Account] {
        let threshold = AppCalendar.gregorian.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let activeAccountIds = Set(
            activeTxns.flatMap { [$0.accountId, $0.counterAccountId].compactMap { $0 } }
        )
        return accounts.filter {
            $0.deletedAt == nil && !$0.isArchived && !$0.isSystem
                && ($0.lastReconciledAt ?? .distantPast) < threshold
                && (activeAccountIds.contains($0.id) || $0.openingBalanceMinor != 0)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                List {
                    if !staleAccounts.isEmpty {
                        Section {
                            NavigationLink {
                                ReconciliationView()
                            } label: {
                                HStack(spacing: Theme.Spacing.s) {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundStyle(Theme.warning)
                                    Text("有 \(staleAccounts.count) 个账户超过 30 天未对账")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("去对账")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section {
                        periodBar
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(Color.clear)

                        monthSummaryCard
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        accountStrip
                            .listRowInsets(EdgeInsets())
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SearchView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $showEntry) {
                EntrySheet()
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showCustomRange) {
                customRangeSheet
                    .presentationDetents([.height(300)])
            }
            .onAppear {
                customStart = period.customStart ?? AppCalendar.startOfMonth(Date())
                customEnd = period.customEnd ?? Date()
            }
        }
    }

    // MARK: - 周期切换

    private var periodBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button {
                period = period.shifted(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(period.kind == .custom)

            Spacer()

            Menu {
                ForEach(PeriodKind.allCases) { kind in
                    Button(kind.displayName) {
                        if kind == .custom {
                            showCustomRange = true
                        } else {
                            period = PeriodRange(kind: kind, anchor: period.anchor)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(period.title())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                period = period.shifted(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(period.kind == .custom)
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("开始", selection: $customStart, displayedComponents: .date)
                DatePicker("结束", selection: $customEnd, in: customStart..., displayedComponents: .date)
            }
            .navigationTitle("自定义区间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showCustomRange = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        period = PeriodRange(
                            kind: .custom,
                            anchor: customStart,
                            customStart: customStart,
                            customEnd: customEnd
                        )
                        showCustomRange = false
                    }
                }
            }
        }
    }

    // MARK: - 汇总

    private var monthSummaryCard: some View {
        HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(period.kind.summaryLabel)支出")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(Money.format(periodExpense))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: Theme.Spacing.s)
            summaryItem(title: "收入", value: Money.format(periodIncome), color: Theme.income)
            summaryItem(title: "结余", value: Money.format(periodIncome - periodExpense), color: .primary)
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

    /// 首页账户横滑卡片
    private var cardAccounts: [Account] {
        accounts
            .filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var accountStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.m) {
                ForEach(cardAccounts, id: \.id) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        accountCard(account)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, 2)
        }
    }

    private func accountCard(_ account: Account) -> some View {
        let balance = BalanceService.balance(
            of: account,
            transactions: activeTxns,
            openingBalanceMinor: account.openingBalanceMinor
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                BankMarkView(
                    bankId: account.bankId,
                    fallbackEmoji: account.iconEmoji,
                    fallbackColorHex: account.colorHex,
                    size: 22
                )
                Text(account.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            Text(Money.format(balance))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(balance < 0 ? Theme.danger : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(width: 132, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("\(period.title())没有记录")
                .font(.headline)
            Text("点右下角的 + 记一笔")
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
        accounts.first { $0.id == txn.accountId }?.displayName ?? "—"
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
