import SwiftUI
import SwiftData

struct ClaimDetailView: View {
    let claim: Claim

    @Environment(\.modelContext) private var context
    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var categories: [Category]
    @Query private var accounts: [Account]

    @State private var showReceive = false
    @State private var receiveText = ""
    @State private var receiveAccountId: UUID?

    private var items: [Txn] {
        allTxns.filter { $0.deletedAt == nil && $0.claimId == claim.id && $0.type == .expense }
    }

    private var totalMinor: Int64 {
        items.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private struct CategoryTotal: Identifiable {
        let id: UUID
        let name: String
        let emoji: String
        let amountMinor: Int64
    }

    private var byCategory: [CategoryTotal] {
        var totals: [UUID: Int64] = [:]
        var unknown: Int64 = 0
        for item in items {
            if let categoryId = item.categoryId {
                totals[categoryId, default: 0] += item.amountMinor
            } else {
                unknown += item.amountMinor
            }
        }
        var result: [CategoryTotal] = totals.map { pair in
            let category = categories.first { $0.id == pair.key }
            return CategoryTotal(
                id: pair.key,
                name: category?.name ?? "未分类",
                emoji: category?.iconEmoji ?? "❓",
                amountMinor: pair.value
            )
        }
        if unknown > 0 {
            result.append(
                CategoryTotal(id: StatsEngine.uncategorizedId, name: "未分类", emoji: "❓", amountMinor: unknown)
            )
        }
        return result.sorted { $0.amountMinor > $1.amountMinor }
    }

    private var receivableAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem && !$0.type.isLiability }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("合计")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Money.format(totalMinor))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("\(items.count) 笔 · \(claim.periodMonth) · \(claim.status.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            Section("按分类小计") {
                if byCategory.isEmpty {
                    Text("暂无条目").foregroundStyle(.secondary)
                }
                ForEach(byCategory) { item in
                    HStack {
                        Text(item.emoji)
                        Text(item.name)
                        Spacer()
                        Text(Money.format(item.amountMinor)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }

            Section("条目") {
                if items.isEmpty {
                    Text("还没有关联的支出").foregroundStyle(.secondary)
                }
                ForEach(items, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.note?.isEmpty == false ? (item.note ?? "") : (categories.first { $0.id == item.categoryId }?.name ?? "未分类"))
                                .font(.subheadline)
                            Text(DateFormatter.ledgerShort.string(from: item.occurredAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.format(item.amountMinor)).monospacedDigit()
                    }
                }
            }

            Section {
                if claim.status == .draft {
                    Button("提交报销") { submit() }
                }
                if claim.status == .submitted {
                    Button("登记到账") {
                        receiveText = Money.rawText(totalMinor)
                        receiveAccountId = receivableAccounts.first?.id
                        showReceive = true
                    }
                }
                if claim.status == .draft || claim.status == .submitted {
                    Button(role: .destructive) { close() } label: {
                        Text("报不掉，关闭该报销单")
                    }
                }
                if claim.status == .reimbursed {
                    LabeledContent("实际到账", value: Money.format(claim.receivedAmountMinor ?? 0))
                    if claim.shortfallMinor > 0 {
                        LabeledContent("差额", value: Money.format(claim.shortfallMinor))
                    }
                }
            }
        }
        .navigationTitle(claim.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReceive) {
            receiveSheet
                .presentationDetents([.medium])
        }
    }

    private var receiveSheet: some View {
        NavigationStack {
            Form {
                Section("到账金额") {
                    TextField("0.00", text: $receiveText)
                        .keyboardType(.decimalPad)
                }
                Section("到账账户") {
                    Picker("账户", selection: $receiveAccountId) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(receivableAccounts, id: \.id) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }
            }
            .navigationTitle("登记到账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showReceive = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { receive() }
                        .disabled(receiveAccountId == nil)
                }
            }
        }
    }

    private func submit() {
        claim.status = .submitted
        claim.submittedAt = Date()
        claim.updatedAt = Date()
        try? context.save()
        Haptics.success()
    }

    private func close() {
        claim.status = .closed
        claim.updatedAt = Date()
        try? context.save()
        Haptics.warning()
    }

    private func receive() {
        guard let accountId = receiveAccountId,
              let amount = Money.parse(receiveText) else { return }

        let categoryId = categories.first { $0.name == "报销收入" && $0.kind == .income }?.id
        let income = Txn(
            bookId: claim.bookId,
            type: .income,
            amountMinor: amount,
            accountId: accountId,
            categoryId: categoryId,
            note: "报销到账 · \(claim.title)"
        )
        income.claimId = claim.id
        context.insert(income)

        claim.status = .reimbursed
        claim.reimbursedAt = Date()
        claim.receivedAmountMinor = amount
        claim.receivedAccountId = accountId
        claim.shortfallMinor = max(0, totalMinor - amount)
        claim.updatedAt = Date()

        try? context.save()

        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        try? context.save()

        Haptics.success()
        showReceive = false
    }
}
