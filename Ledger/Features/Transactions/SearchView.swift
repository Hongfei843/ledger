import SwiftUI
import SwiftData

struct SearchView: View {
    @Query(
        filter: #Predicate<Txn> { $0.deletedAt == nil },
        sort: \Txn.occurredAt,
        order: .reverse
    ) private var allTxns: [Txn]
    @Query private var categories: [Category]
    @Query private var accounts: [Account]

    @State private var keyword = ""
    @State private var typeFilter: TxnType?
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var currentPeriodOnly = false

    private var results: [Txn] {
        let interval = AppCalendar.monthInterval(containing: Date())
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return allTxns.filter { txn in
            if currentPeriodOnly && !interval.contains(txn.occurredAt) { return false }
            if let typeFilter, txn.type != typeFilter { return false }
            if let accountId, txn.accountId != accountId && txn.counterAccountId != accountId { return false }
            if let categoryId, txn.categoryId != categoryId { return false }

            guard !query.isEmpty else { return true }
            if let note = txn.note?.lowercased(), note.contains(query) { return true }
            if let payee = txn.payee?.lowercased(), payee.contains(query) { return true }
            if let category = categories.first(where: { $0.id == txn.categoryId }),
               category.name.lowercased().contains(query) { return true }
            if let account = accounts.first(where: { $0.id == txn.accountId }),
               account.name.lowercased().contains(query) { return true }
            // 按金额搜：输入 38 或 38.5
            if let amount = Money.parse(query), amount == txn.amountMinor { return true }
            return false
        }
    }

    private var expenseTotal: Int64 {
        results.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var incomeTotal: Int64 {
        results.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    var body: some View {
        List {
            Section {
                filters
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            Section {
                HStack {
                    Text("\(results.count) 笔")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("支出 \(Money.format(expenseTotal)) · 收入 \(Money.format(incomeTotal))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if results.isEmpty {
                    Text(keyword.isEmpty && typeFilter == nil && accountId == nil && categoryId == nil
                         ? "输入关键词开始搜索"
                         : "没有匹配的记录")
                        .foregroundStyle(.secondary)
                }
                ForEach(results.prefix(200), id: \.id) { txn in
                    NavigationLink {
                        TxnDetailView(txn: txn)
                    } label: {
                        row(txn)
                    }
                }
            }
        }
        .searchable(text: $keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "备注、商家、分类、账户或金额")
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                Menu {
                    Button("全部") { typeFilter = nil }
                    ForEach([TxnType.expense, .income, .transfer, .adjustment], id: \.self) { type in
                        Button(type.displayName) { typeFilter = type }
                    }
                } label: {
                    chip(typeFilter?.displayName ?? "全部类型", active: typeFilter != nil)
                }

                Menu {
                    Button("全部账户") { accountId = nil }
                    ForEach(accounts.filter { $0.deletedAt == nil && !$0.isSystem }, id: \.id) { account in
                        Button(account.displayName) { accountId = account.id }
                    }
                } label: {
                    chip(accountLabel, active: accountId != nil)
                }

                Menu {
                    Button("全部分类") { categoryId = nil }
                    ForEach(categories.filter { $0.deletedAt == nil && !$0.isArchived }, id: \.id) { category in
                        Button("\(category.iconEmoji) \(category.name)") { categoryId = category.id }
                    }
                } label: {
                    chip(categoryLabel, active: categoryId != nil)
                }

                Button {
                    currentPeriodOnly.toggle()
                } label: {
                    chip("仅本月", active: currentPeriodOnly)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
    }

    private var accountLabel: String {
        guard let accountId, let account = accounts.first(where: { $0.id == accountId }) else {
            return "全部账户"
        }
        return account.name
    }

    private var categoryLabel: String {
        guard let categoryId, let category = categories.first(where: { $0.id == categoryId }) else {
            return "全部分类"
        }
        return category.name
    }

    private func chip(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 6)
            .background(active ? Theme.accent.opacity(0.16) : Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(active ? Theme.accent : .primary)
    }

    private func row(_ txn: Txn) -> some View {
        let category = categories.first { $0.id == txn.categoryId }
        let account = accounts.first { $0.id == txn.accountId }
        let sign = txn.type == .income ? "+" : (txn.type == .expense ? "-" : "")

        return HStack(spacing: Theme.Spacing.m) {
            CategoryIconView(category: category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(category?.name ?? txn.type.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(DateFormatter.ledgerShort.string(from: txn.occurredAt)) · \(account?.displayName ?? "—")\(txn.note.map { " · \($0)" } ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(sign + Money.format(abs(txn.amountMinor)))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(txn.type == .income ? Theme.income : .primary)
        }
    }
}
