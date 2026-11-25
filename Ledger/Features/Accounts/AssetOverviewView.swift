import SwiftUI
import SwiftData

/// 资产总览：一屏看清总资产、总负债、净资产与结构。
struct AssetOverviewView: View {
    @Query private var accounts: [Account]
    @Query private var allTxns: [Txn]

    private var liveAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived }
    }

    private var liveTxns: [Txn] {
        allTxns.filter { $0.deletedAt == nil }
    }

    private func balance(_ account: Account) -> Int64 {
        BalanceService.balance(
            of: account,
            transactions: liveTxns,
            openingBalanceMinor: account.openingBalanceMinor
        )
    }

    private var assetAccounts: [Account] {
        liveAccounts.filter { !$0.type.isLiability }.sorted { balance($0) > balance($1) }
    }

    private var liabilityAccounts: [Account] {
        liveAccounts.filter { $0.type.isLiability }.sorted { balance($0) < balance($1) }
    }

    private var totalAssets: Int64 {
        assetAccounts.filter { $0.includeInNetWorth }.reduce(Int64(0)) { $0 + balance($1) }
    }

    private var totalLiabilities: Int64 {
        liabilityAccounts.filter { $0.includeInNetWorth }.reduce(Int64(0)) { $0 + abs(balance($1)) }
    }

    private var netWorth: Int64 {
        totalAssets - totalLiabilities
    }

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
