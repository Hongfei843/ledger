import SwiftUI
import SwiftData

/// 某个分类在指定时间范围内的明细列表（从统计页下钻进入）
struct CategoryTxnListView: View {
    let categoryId: UUID
    let range: DateInterval
    let title: String
    let caliber: StatsCaliber

    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var claims: [Claim]

    private var openClaims: Set<UUID> { StatsEngine.openClaimIds(claims: claims) }
    private var claimsById: [UUID: Claim] { Dictionary(uniqueKeysWithValues: claims.map { ($0.id, $0) }) }

    /// 退款归到「原支出」的分类，与统计页的分类构成保持同一归属。
    private func displayCategoryId(_ txn: Txn) -> UUID {
        if RefundService.isRefund(txn),
           let originalId = txn.refundOfTxnId,
           let original = allTxns.first(where: { $0.id == originalId && $0.deletedAt == nil }) {
            return original.categoryId ?? StatsEngine.uncategorizedId
        }
        return txn.categoryId ?? StatsEngine.uncategorizedId
    }

    private var items: [Txn] {
        allTxns.filter { txn in
            guard txn.deletedAt == nil,
                  range.contains(txn.occurredAt),
                  displayCategoryId(txn) == categoryId else { return false }
            return StatsEngine.includesExpense(txn, caliber: caliber, openClaims: openClaims, claimsById: claimsById)
                || StatsEngine.includesRefund(txn, caliber: caliber, allTxns: allTxns, openClaims: openClaims, claimsById: claimsById)
        }
    }

    private var expenseItems: [Txn] {
        items.filter { StatsEngine.includesExpense($0, caliber: caliber, openClaims: openClaims, claimsById: claimsById) }
    }

    private var totalMinor: Int64 {
        let gross = expenseItems.reduce(Int64(0)) { $0 + $1.amountMinor }
        let refunds = items.filter { RefundService.isRefund($0) }.reduce(Int64(0)) { $0 + $1.amountMinor }
        return max(0, gross - refunds)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("合计").foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.format(totalMinor))
                        .font(Theme.Fonts.amountM)
                        .monospacedDigit()
                }
                HStack {
                    Text("笔数").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(expenseItems.count)")
                }
                if expenseItems.count > 1 {
                    HStack {
                        Text("单笔均值").foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.format(totalMinor / Int64(expenseItems.count)))
                            .monospacedDigit()
                    }
                }
            }

            Section {
                if items.isEmpty {
                    Text("该时间段内没有记录").foregroundStyle(.secondary)
                }
                ForEach(items, id: \.id) { txn in
                    NavigationLink {
                        TxnDetailView(txn: txn)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(txn.note?.isEmpty == false ? (txn.note ?? "") : (categories.first { $0.id == txn.categoryId }?.name ?? "未分类"))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text("\(DateFormatter.ledgerShort.string(from: txn.occurredAt)) · \(accounts.first { $0.id == txn.accountId }?.name ?? "—")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((RefundService.isRefund(txn) ? "-" : "") + Money.format(txn.amountMinor))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(RefundService.isRefund(txn) ? Theme.income : .primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
