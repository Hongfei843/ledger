import SwiftUI
import SwiftData

/// 某个分类在指定时间范围内的明细列表（从统计页下钻进入）
struct CategoryTxnListView: View {
    let categoryId: UUID
    let range: DateInterval
    let title: String

    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    private var items: [Txn] {
        allTxns.filter {
            $0.deletedAt == nil && $0.categoryId == categoryId && range.contains($0.occurredAt)
        }
    }

    private var totalMinor: Int64 {
        items.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("合计").foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.format(totalMinor))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                HStack {
                    Text("笔数").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(items.count)")
                }
                if items.count > 1 {
                    HStack {
                        Text("单笔均值").foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.format(totalMinor / Int64(items.count)))
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
                            Text(Money.format(txn.amountMinor))
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
