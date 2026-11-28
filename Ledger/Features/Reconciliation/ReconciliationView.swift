import SwiftUI
import SwiftData

/// 对账页：一屏看到所有账户的「账面 vs 实际」，填完一起校准。
/// 目的：把对账从「散落在各账户详情里」变成一个可完成的任务。
struct ReconciliationView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var allTxns: [Txn]
    @AppStorage(BookScope.key) private var currentBookRaw = ""

    @State private var inputs: [UUID: String] = [:]
    @State private var message: String?

    @Query(sort: \ReconciliationRun.createdAt, order: .reverse) private var runs: [ReconciliationRun]

    private var liveAccounts: [Account] {
        accounts
            .filter {
                $0.deletedAt == nil && !$0.isArchived && !$0.isSystem
                    && BookScope.matches($0.bookId, raw: currentBookRaw)
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var liveTxns: [Txn] {
        allTxns.filter { $0.deletedAt == nil && BookScope.matches($0.bookId, raw: currentBookRaw) }
    }

    private var assets: [Account] { liveAccounts.filter { !$0.type.isLiability } }
    private var liabilities: [Account] { liveAccounts.filter { $0.type.isLiability } }

    private var recentRuns: [ReconciliationRun] {
        runs.filter { BookScope.matches($0.bookId, raw: currentBookRaw) }
    }

    private var pendingCount: Int {
        liveAccounts.filter { account in
            guard let text = inputs[account.id] else { return false }
            return Money.parse(text) != nil
        }.count
    }

    private var staleCount: Int {
        let threshold = AppCalendar.gregorian.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return liveAccounts.filter { ($0.lastReconciledAt ?? .distantPast) < threshold }.count
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("未对账账户")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(staleCount) 个")
                            .font(.headline)
                            .foregroundStyle(staleCount > 0 ? Theme.warning : Theme.income)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("已填写")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(pendingCount) 个")
                            .font(.headline)
                    }
                }
            } footer: {
                Text("超过 30 天没对账的账户会计入上方。填了实际余额才会参与校准。")
            }

            section(title: "资产", accounts: assets)
            section(title: "负债", accounts: liabilities)

            Section {
                Button {
                    applyAll()
                } label: {
                    Text("保存并校准（\(pendingCount) 个）")
                        .frame(maxWidth: .infinity)
                }
                .disabled(pendingCount == 0)

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.income)
                }
            }

            if !recentRuns.isEmpty {
                Section {
                    ForEach(recentRuns.prefix(5), id: \.id) { run in
                        HStack {
                            Text(DateFormatter.ledgerDateTime.string(from: run.createdAt))
                                .font(.subheadline)
                            Spacer()
                            if run.diffCount == 0 {
                                Text("全部一致")
                                    .font(.caption)
                                    .foregroundStyle(Theme.income)
                            } else {
                                Text("\(run.diffCount) 处差异 · \(Money.format(run.totalDiffMinor))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.warning)
                            }
                        }
                    }
                } header: {
                    Text("最近对账")
                } footer: {
                    Text("每次保存校准都会留一条记录，方便回头查「这个月账到底差了多少」。")
                }
            }
        }
        .navigationTitle("对账")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(title: String, accounts: [Account]) -> some View {
        Section(title) {
            if accounts.isEmpty {
                Text("暂无账户").foregroundStyle(.secondary)
            }
            ForEach(accounts, id: \.id) { account in
                row(account)
            }
        }
    }

    private func row(_ account: Account) -> some View {
        let current = BalanceService.balance(
            of: account,
            transactions: liveTxns,
            openingBalanceMinor: account.openingBalanceMinor
        )
        let actualInput = inputs[account.id].flatMap { Money.parse($0) }
        let actual = actualInput.map { BalanceService.signedBalance(fromActualInput: $0, accountType: account.type) }
        let delta = actual.map { $0 - current }
        let displayDelta = delta.map { BalanceService.displayBalance($0, accountType: account.type) }

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.iconEmoji)
                Text(account.name).font(.subheadline)
                Spacer()
                Text(Money.format(BalanceService.displayBalance(current, accountType: account.type)))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Spacing.s) {
                TextField(account.type.isLiability ? "实际欠款" : "实际余额", text: binding(for: account.id))
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)

                if let displayDelta {
                    Text(displayDelta == 0 ? "一致" : Money.format(displayDelta, showSign: true))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(displayDelta == 0 ? Theme.income : Theme.warning)
                        .frame(width: 90, alignment: .trailing)
                }
            }
            Text(reconcileHint(account))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func reconcileHint(_ account: Account) -> String {
        let base = account.lastReconciledAt.map {
            "上次对账 \(DateFormatter.ledgerShort.string(from: $0))"
        } ?? "从未对账"
        return account.type.isLiability ? "\(base) · 填全部欠款，溢缴填负数" : base
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { inputs[id] ?? "" },
            set: { inputs[id] = $0 }
        )
    }

    private func applyAll() {
        var adjusted = 0
        var diffTotal: Int64 = 0
        var checkedCount = 0
        let now = Date()

        for account in liveAccounts {
            guard let text = inputs[account.id], let actualInput = Money.parse(text) else { continue }
            let actual = BalanceService.signedBalance(fromActualInput: actualInput, accountType: account.type)
            checkedCount += 1
            let current = BalanceService.balance(
                of: account,
                transactions: liveTxns,
                openingBalanceMinor: account.openingBalanceMinor
            )
            let delta = actual - current
            if delta != 0 {
                let txn = Txn(
                    bookId: account.bookId,
                    type: .adjustment,
                    amountMinor: delta,
                    accountId: account.id,
                    note: "对账校准"
                )
                context.insert(txn)
                adjusted += 1
                diffTotal += abs(delta)
            }
            account.lastReconciledAt = now
            account.updatedAt = now
        }

        if checkedCount > 0 {
            let bookId = liveAccounts.first?.bookId ?? UUID()
            let run = ReconciliationRun(
                bookId: bookId,
                accountCount: checkedCount,
                diffCount: adjusted,
                totalDiffMinor: diffTotal
            )
            context.insert(run)
        }

        PersistenceGuard.save(context, "保存对账结果")

        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        PersistenceGuard.save(context, "保存对账结果")

        inputs = [:]
        message = adjusted == 0 ? "账面与实际全部一致，对账时间已更新" : "已校准 \(adjusted) 个账户"
        Haptics.success()
    }
}
