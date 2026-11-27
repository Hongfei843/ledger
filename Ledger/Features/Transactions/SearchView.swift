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
    @AppStorage(BookScope.key) private var currentBookRaw = ""

    @State private var criteria = TxnSearchCriteria()

    private var results: [Txn] {
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.displayName) })
        return allTxns.filter { txn in
            guard BookScope.matches(txn.bookId, raw: currentBookRaw) else { return false }
            return criteria.matches(
                txn,
                categoryName: txn.categoryId.flatMap { categoryMap[$0] },
                accountName: accountMap[txn.accountId]
            )
        }
    }

    private var refundTotal: Int64 {
        results.filter { RefundService.isRefund($0) }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var expenseTotal: Int64 {
        let gross = results.filter { $0.type == .expense && $0.source != .reimbursement }.reduce(Int64(0)) { $0 + $1.amountMinor }
        return RefundService.netExpense(expenseMinor: gross, refundMinor: refundTotal)
    }

    private var incomeTotal: Int64 {
        results
            .filter { $0.type == .income && !RefundService.isRefund($0) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
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
                if refundTotal > 0 {
                    Text("已按退款冲减 \(Money.format(refundTotal))")
                        .font(.caption2)
                        .foregroundStyle(Theme.income)
                }
            }

            Section {
                if results.isEmpty {
                    Text(criteria.isActive ? "没有匹配的记录" : "输入关键词，或点上面的筛选项")
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
        .searchable(text: $criteria.keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "备注、商家、分类、账户或金额")
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 筛选

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                Menu {
                    Button("全部类型") { criteria.types = [] }
                    ForEach([TxnType.expense, .income, .transfer, .adjustment], id: \.self) { type in
                        Button(type.displayName) { criteria.types = [type] }
                    }
                } label: {
                    chip(typeLabel, active: !criteria.types.isEmpty)
                }

                Menu {
                    Button("全部账户") { criteria.accountId = nil }
                    ForEach(accounts.filter { $0.deletedAt == nil && !$0.isSystem && BookScope.matches($0.bookId, raw: currentBookRaw) }, id: \.id) { account in
                        Button(account.displayName) { criteria.accountId = account.id }
                    }
                } label: {
                    chip(accountLabel, active: criteria.accountId != nil)
                }

                Menu {
                    Button("全部分类") { criteria.categoryId = nil }
                    ForEach(categories.filter { $0.deletedAt == nil && !$0.isArchived && BookScope.matches($0.bookId, raw: currentBookRaw) }, id: \.id) { category in
                        Button("\(category.iconEmoji) \(category.name)") { criteria.categoryId = category.id }
                    }
                } label: {
                    chip(categoryLabel, active: criteria.categoryId != nil)
                }

                Menu {
                    Button("全部金额") { criteria.minAmountMinor = nil; criteria.maxAmountMinor = nil }
                    Button("100 元以下") { criteria.minAmountMinor = nil; criteria.maxAmountMinor = 10_000 }
                    Button("100 – 500 元") { criteria.minAmountMinor = 10_000; criteria.maxAmountMinor = 50_000 }
                    Button("500 – 2000 元") { criteria.minAmountMinor = 50_000; criteria.maxAmountMinor = 200_000 }
                    Button("2000 元以上") { criteria.minAmountMinor = 200_000; criteria.maxAmountMinor = nil }
                } label: {
                    chip(amountLabel, active: criteria.minAmountMinor != nil || criteria.maxAmountMinor != nil)
                }

                Menu {
                    ForEach(SearchDateScope.allCases) { scope in
                        Button(scope.displayName) { criteria.dateScope = scope }
                    }
                } label: {
                    chip(criteria.dateScope.displayName, active: criteria.dateScope != .all)
                }

                Button {
                    criteria.onlyReimbursable.toggle()
                } label: {
                    chip("可报销", active: criteria.onlyReimbursable)
                }
                .buttonStyle(.plain)

                Button {
                    criteria.onlyRefunds.toggle()
                } label: {
                    chip("退款", active: criteria.onlyRefunds)
                }
                .buttonStyle(.plain)

                if criteria.isActive {
                    Button {
                        criteria = TxnSearchCriteria()
                    } label: {
                        chip("清空", active: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var typeLabel: String {
        guard let type = criteria.types.first else { return "全部类型" }
        return type.displayName
    }

    private var accountLabel: String {
        guard let accountId = criteria.accountId,
              let account = accounts.first(where: { $0.id == accountId }) else {
            return "全部账户"
        }
        return account.name
    }

    private var categoryLabel: String {
        guard let categoryId = criteria.categoryId,
              let category = categories.first(where: { $0.id == categoryId }) else {
            return "全部分类"
        }
        return category.name
    }

    private var amountLabel: String {
        let min = criteria.minAmountMinor
        let max = criteria.maxAmountMinor
        switch (min, max) {
        case (nil, nil): return "全部金额"
        case (nil, 10_000): return "100 元以下"
        case (10_000, 50_000): return "100 – 500 元"
        case (50_000, 200_000): return "500 – 2000 元"
        case (200_000, nil): return "2000 元以上"
        default:
            if let min, let max { return "\(Money.format(min)) – \(Money.format(max))" }
            if let min { return "≥ \(Money.format(min))" }
            if let max { return "≤ \(Money.format(max))" }
            return "全部金额"
        }
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
                HStack(spacing: 4) {
                    Text(category?.name ?? txn.type.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                    if txn.isRefund {
                        Text("退款")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.income.opacity(0.14), in: Capsule())
                            .foregroundStyle(Theme.income)
                    }
                }
                Text("\(DateFormatter.ledgerShort.string(from: txn.occurredAt)) · \(account?.displayName ?? "—")\(txn.note.map { " · \($0)" } ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(sign + Money.format(abs(txn.amountMinor)))
                .font(Theme.Fonts.amountM)
                .monospacedDigit()
                .foregroundStyle(txn.type == .income ? Theme.income : .primary)
        }
    }
}
