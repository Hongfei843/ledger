import SwiftUI
import SwiftData
import Charts

/// 资产总览：一屏看清总资产、总负债、净资产与结构。
struct AssetOverviewView: View {
    @Query private var accounts: [Account]
    @Query private var allTxns: [Txn]
    @AppStorage(BookScope.key) private var currentBookRaw = ""

    private func bookMatches(_ id: UUID) -> Bool { BookScope.matches(id, raw: currentBookRaw) }

    private var liveAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && bookMatches($0.bookId) }
    }

    private var liveTxns: [Txn] {
        allTxns.filter { $0.deletedAt == nil && bookMatches($0.bookId) }
    }

    private func balance(_ account: Account) -> Int64 {
        BalanceService.balance(
            of: account,
            transactions: liveTxns,
            openingBalanceMinor: account.openingBalanceMinor
        )
    }

    private var assetAccounts: [Account] {
        liveAccounts.filter { !$0.type.isLiability && $0.includeInNetWorth && !$0.isSystem }.sorted { balance($0) > balance($1) }
    }

    private var liabilityAccounts: [Account] {
        liveAccounts.filter { $0.type.isLiability && $0.type != .loan && $0.includeInNetWorth && !$0.isSystem }.sorted { balance($0) < balance($1) }
    }

    private var totals: NetWorthTotals {
        BalanceService.totals(accounts: liveAccounts, transactions: liveTxns, bookId: BookScope.currentId)
    }

    private var totalAssets: Int64 { totals.assetsMinor }

    private var totalLiabilities: Int64 { totals.liabilitiesMinor }

    private var netWorth: Int64 { totals.netWorthMinor }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("净资产")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Money.format(netWorth))
                        .font(Theme.Fonts.amountXL)
                        .monospacedDigit()
                        .foregroundStyle(netWorth < 0 ? Theme.danger : .primary)

                    HStack(spacing: Theme.Spacing.xl) {
                        summary("总资产", Money.format(totalAssets), Theme.income)
                        summary("总负债", Money.format(totalLiabilities), Theme.warning)
                    }
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            Section {
                if history.count >= 2 {
                    Chart(history) { point in
                        LineMark(
                            x: .value("月份", monthLabel(point)),
                            y: .value("净资产", Double(point.netWorthMinor) / 100.0)
                        )
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("月份", monthLabel(point)),
                            y: .value("净资产", Double(point.netWorthMinor) / 100.0)
                        )
                        .foregroundStyle(Theme.accent.opacity(0.12))
                    }
                    .frame(height: 150)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let yuan = value.as(Double.self) {
                                    Text(shortYuan(yuan))
                                }
                            }
                        }
                    }

                    if let latest = history.last {
                        HStack(spacing: Theme.Spacing.m) {
                            Text("本月净资产 \(Money.format(latest.netWorthMinor))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let delta = latestDelta {
                                Text(deltaText(delta))
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(delta >= 0 ? Theme.income : Theme.danger)
                            }
                        }
                    }
                } else {
                    Text("数据还太少，记几笔后这里会自动生成趋势。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("净资产趋势")
            } footer: {
                Text("按每个月最后一天重算余额，当前月份截止今天；贷款账户不重复计入。")
            }

            Section("资产结构") {
                if assetAccounts.isEmpty {
                    Text("暂无资产账户").foregroundStyle(.secondary)
                }
                ForEach(assetAccounts, id: \.id) { account in
                    row(account, ratioBase: totalAssets)
                }
            }

            Section("负债结构") {
                if liabilityAccounts.isEmpty {
                    Text("暂无负债").foregroundStyle(.secondary)
                }
                ForEach(liabilityAccounts, id: \.id) { account in
                    row(account, ratioBase: totalLiabilities)
                }
            }
        }
        .navigationTitle("资产总览")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 趋势

    private var history: [NetWorthPoint] {
        NetWorthHistory.monthly(months: 6, accounts: liveAccounts, transactions: liveTxns)
    }

    private var latestDelta: Int64? {
        guard history.count >= 2, let last = history.last else { return nil }
        return last.netWorthMinor - history[history.count - 2].netWorthMinor
    }

    private func deltaText(_ delta: Int64) -> String {
        let prefix = delta >= 0 ? "+" : "-"
        return prefix + Money.format(abs(delta)) + " 较上月"
    }

    private func monthLabel(_ point: NetWorthPoint) -> String {
        String(point.id.suffix(2)) + "月"
    }

    private func shortYuan(_ yuan: Double) -> String {
        if abs(yuan) >= 10_000 { return String(format: "%.1f万", yuan / 10_000) }
        return String(format: "%.0f", yuan)
    }

    private func summary(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(Theme.Fonts.amountS)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func row(_ account: Account, ratioBase: Int64) -> some View {
        let value = abs(balance(account))
        let ratio = ratioBase > 0 ? Double(value) / Double(ratioBase) : 0

        return VStack(spacing: 5) {
            HStack {
                Text(account.iconEmoji)
                Text(account.name).font(.subheadline)
                Spacer()
                Text(Money.format(value))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(account.type.isLiability ? Theme.warning : .primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.secondarySystemBackground))
                    Capsule()
                        .fill(account.type.isLiability ? Theme.warning : Theme.accent)
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 4)
            HStack {
                Text(account.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", ratio * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 3)
    }
}
