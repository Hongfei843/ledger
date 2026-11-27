import SwiftUI
import SwiftData

/// 资产 Tab：净资产、投资持仓、账户、负债都在这一页，首页只留摘要和明细。
struct AssetsHomeView: View {
    @Query private var accounts: [Account]
    @Query private var allTxns: [Txn]
    @Query private var loans: [Loan]
    @Query private var statements: [Statement]
    @Query private var debts: [Debt]
    @AppStorage(BookScope.key) private var currentBookRaw = ""

    private func bookMatches(_ id: UUID) -> Bool { BookScope.matches(id, raw: currentBookRaw) }

    private var liveTxns: [Txn] { allTxns.filter { $0.deletedAt == nil && bookMatches($0.bookId) } }
    private var liveAccounts: [Account] {
        accounts
            .filter { $0.deletedAt == nil && !$0.isArchived && bookMatches($0.bookId) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    private var liveStatements: [Statement] {
        let accountIds = Set(liveAccounts.map { $0.id })
        return statements.filter { accountIds.contains($0.accountId) }
    }
    private var liveDebts: [Debt] { debts.filter { $0.deletedAt == nil && bookMatches($0.bookId) } }
    private var balances: [UUID: Int64] {
        var map: [UUID: Int64] = [:]
        for account in liveAccounts {
            map[account.id] = BalanceService.balance(
                of: account,
                transactions: liveTxns,
                openingBalanceMinor: account.openingBalanceMinor
            )
        }
        return map
    }

    private var netWorthTotals: NetWorthTotals {
        BalanceService.totals(accounts: accounts, transactions: allTxns, bookId: BookScope.currentId)
    }

    private var assetTotalMinor: Int64 { netWorthTotals.assetsMinor }
    private var liabilityTotalMinor: Int64 { netWorthTotals.liabilitiesMinor }
    private var displayAccounts: [Account] { liveAccounts.filter { !$0.isSystem } }

    private var creditDebtMinor: Int64 {
        liveAccounts.filter { $0.type.isCreditLike }.reduce(Int64(0)) { partial, account in
            guard let info = CreditCardBillService.info(for: account, txns: liveTxns, statements: liveStatements) else {
                return partial
            }
            let amount = info.registered?.outstandingMinor ?? info.estimatedAmountMinor
            return partial + max(0, amount)
        }
    }

    private var loanOutstandingMinor: Int64 {
        loans
            .filter { $0.deletedAt == nil && $0.status == .active && bookMatches($0.bookId) }
            .reduce(Int64(0)) { $0 + $1.outstandingPrincipalMinor }
    }

    private var debtSummary: (receivable: Int64, payable: Int64) {
        DebtService.summary(liveDebts)
    }

    private var netWorthMinor: Int64 {
        netWorthTotals.netWorthMinor
    }

    private var portfolio: InvestmentPortfolio {
        InvestmentService.portfolio(accounts: liveAccounts, txns: liveTxns)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    netWorthCard
                    if !portfolio.positions.isEmpty {
                        investmentCard
                    }
                    accountsCard
                    liabilitiesCard
                    quickLinks
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
            }
            .background(Theme.pageBackground)
            .navigationTitle("资产")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("管理账户")
                }
            }
        }
    }

    // MARK: - 净值

    private var netWorthCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Label("净资产", systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("资产 − 负债")
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.76))

            Text(Money.format(netWorthMinor))
                .font(Theme.Fonts.amountXL)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.52)

            HStack(spacing: Theme.Spacing.xl) {
                heroStat(title: "总资产", value: Money.format(assetTotalMinor))
                heroStat(title: "总负债", value: Money.format(liabilityTotalMinor))
                heroStat(title: "投资市值", value: Money.format(portfolio.valueMinor))
            }

            if loanOutstandingMinor > 0 {
                Label("贷款按计划单列 \(Money.format(loanOutstandingMinor))，不重复计入", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 170, height: 170)
                .offset(x: 58, y: -74)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.22), radius: 24, x: 0, y: 12)
    }

    private func heroStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 投资

    private var investmentCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("投资理财").font(.headline)
                Spacer()
                if let rate = portfolio.ratePercent {
                    Text(String(format: "%+.2f%%", rate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(rate >= 0 ? Theme.income : Theme.danger)
                }
            }
            Text(Money.format(portfolio.valueMinor))
                .font(Theme.Fonts.amountM)
                .monospacedDigit()
            HStack(spacing: Theme.Spacing.l) {
                Label("成本 \(Money.format(portfolio.costMinor))", systemImage: "yensign.circle")
                if let profit = portfolio.profitMinor {
                    Label(
                        "浮动盈亏 \(Money.format(profit, showSign: true))",
                        systemImage: profit >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .foregroundStyle(profit >= 0 ? Theme.income : Theme.danger)
                } else {
                    Label("未填成本", systemImage: "questionmark.circle")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            ForEach(portfolio.positions, id: \.accountId) { position in
                if let account = liveAccounts.first(where: { $0.id == position.accountId }) {
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        accountRow(account)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle(padding: Theme.Spacing.l)
    }

    // MARK: - 账户

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("账户").font(.headline)
                Spacer()
                NavigationLink("管理") { AccountsView() }
                    .font(.caption)
            }
            if displayAccounts.isEmpty {
                Text("还没有账户")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(displayAccounts, id: \.id) { account in
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    accountRow(account)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle(padding: Theme.Spacing.l)
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            BankMarkView(
                bankId: account.bankId,
                fallbackEmoji: account.iconEmoji,
                fallbackColorHex: account.colorHex,
                size: 42
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(accountSubtitle(account))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Money.format(BalanceService.displayBalance(balances[account.id] ?? 0, accountType: account.type)))
                .font(Theme.Fonts.amountM)
                .monospacedDigit()
                .foregroundStyle((balances[account.id] ?? 0) < 0 ? Theme.danger : .primary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func accountSubtitle(_ account: Account) -> String {
        let balance = balances[account.id] ?? 0
        if account.type.isCreditLike, let info = CreditCardBillService.info(for: account, txns: liveTxns, statements: liveStatements) {
            let due = DateFormatter.ledgerShort.string(from: info.dueDate)
            if let statement = info.registered {
                return "待还 \(Money.format(statement.outstandingMinor)) · \(due)"
            }
            if info.estimatedAmountMinor > 0 {
                return "本期约 \(Money.format(info.estimatedAmountMinor)) · \(due)"
            }
            return "还款日 \(due)"
        }
        if account.type == .investment,
           let position = InvestmentService.position(for: account, txns: liveTxns),
           position.costMinor > 0 {
            return "成本 \(Money.format(position.costMinor)) · 盈亏 \(Money.format(position.profitMinor ?? 0, showSign: true))"
        }
        return account.includeInNetWorth ? account.type.displayName : "\(account.type.displayName) · 不计净资产"
    }

    // MARK: - 负债

    private var liabilitiesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("负债与往来").font(.headline)

            NavigationLink {
                LoanListView()
            } label: {
                liabilityRow(
                    title: "贷款",
                    detail: "未还本金",
                    amount: loanOutstandingMinor,
                    icon: "house"
                )
            }
            .buttonStyle(.plain)

            liabilityRow(
                title: "信用卡",
                detail: "本期待还",
                amount: creditDebtMinor,
                icon: "creditcard"
            )

            NavigationLink {
                DebtListView()
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(width: 22)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("借入借出").font(.subheadline)
                        Text("应收 \(Money.format(debtSummary.receivable)) · 应付 \(Money.format(debtSummary.payable))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .cardStyle(padding: Theme.Spacing.l)
    }

    private func liabilityRow(title: String, detail: String, amount: Int64, icon: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(amount))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(amount > 0 ? Theme.danger : .secondary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - 快捷入口

    private var quickLinks: some View {
        HStack(spacing: Theme.Spacing.m) {
            quickLink(title: "资产总览", icon: "chart.line.uptrend.xyaxis", destination: AnyView(AssetOverviewView()))
            quickLink(title: "资金计划", icon: "calendar.badge.clock", destination: AnyView(CashFlowPlanView()))
            quickLink(title: "对账", icon: "checklist", destination: AnyView(ReconciliationView()))
        }
    }

    private func quickLink(title: String, icon: String, destination: AnyView) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .cardStyle(radius: 18, padding: Theme.Spacing.m)
        }
        .buttonStyle(.plain)
    }
}
