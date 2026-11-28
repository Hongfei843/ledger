import SwiftUI
import SwiftData

/// 疑似重复记录复核：逐组确认是不是重复，可以「确认不是重复」把它从提醒里去掉。
struct DuplicateReviewView: View {
    @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }, sort: \Txn.occurredAt, order: .reverse)
    private var txns: [Txn]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @AppStorage("health.ignoredDuplicates") private var ignoredRaw: String = ""

    private var ignored: Set<String> {
        Set(ignoredRaw.split(separator: "|").map(String.init))
    }

    private var groups: [(key: String, items: [Txn])] {
        var buckets: [String: [Txn]] = [:]
        for txn in txns {
            let day = AppCalendar.startOfDay(txn.occurredAt).timeIntervalSince1970
            let key = "\(Int(day))|\(txn.typeRaw)|\(txn.amountMinor)|\(txn.accountId.uuidString)|\(txn.counterAccountId?.uuidString ?? "")|\(txn.note ?? "")"
            buckets[key, default: []].append(txn)
        }
        return buckets
            .filter { $0.value.count > 1 && !ignored.contains($0.key) }
            .map { (key: $0.key, items: $0.value.sorted { $0.occurredAt < $1.occurredAt }) }
            .sorted { $0.items[0].occurredAt > $1.items[0].occurredAt }
    }

    var body: some View {
        List {
            if groups.isEmpty {
                Section {
                    Label("没有待确认的重复记录", systemImage: "checkmark.seal")
                        .foregroundStyle(Theme.income)
                }
            }

            ForEach(groups, id: \.key) { group in
                Section {
                    ForEach(group.items, id: \.id) { txn in
                        NavigationLink {
                            TxnDetailView(txn: txn)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(txn.note?.isEmpty == false ? (txn.note ?? "") : (categories.first { $0.id == txn.categoryId }?.name ?? "未分类"))
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text("\(DateFormatter.ledgerShort.string(from: txn.occurredAt)) · \(accounts.first { $0.id == txn.accountId }?.displayName ?? "—")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.format(abs(txn.amountMinor)))
                                    .font(.subheadline)
                                    .monospacedDigit()
                            }
                        }
                    }

                    Button {
                        ignore(group.key)
                    } label: {
                        Label("这些不是重复", systemImage: "hand.thumbsup")
                            .font(.subheadline)
                    }
                } header: {
                    Text("\(group.items.count) 笔金额与日期相同")
                }
            }
        }
        .ledgerTabBarClearance()
        .navigationTitle("重复记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ignore(_ key: String) {
        var set = ignored
        set.insert(key)
        ignoredRaw = set.joined(separator: "|")
        Haptics.success()
    }
}
