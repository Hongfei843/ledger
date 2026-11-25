import Foundation

struct BillCompareResult {
    let totalRows: Int
    let matchedCount: Int
    /// 文件里有、App 里没有 → 漏记
    let missing: [BillRow]
    /// App 里有、文件里没有（限定在文件时间范围内）→ 可能多记
    let extra: [Txn]
}

/// 把账单行与本地流水做匹配：
/// 同方向 + 金额相同 + 日期相差不超过 N 天，一对一消耗。
enum BillMatcher {
    static func compare(
        rows: [BillRow],
        transactions: [Txn],
        windowDays: Int = 1,
        calendar: Calendar = AppCalendar.gregorian
    ) -> BillCompareResult {
        let live = transactions.filter { $0.deletedAt == nil && ($0.type == .expense || $0.type == .income) }
        var used = Set<UUID>()
        var missing: [BillRow] = []
        var matched = 0

        let sortedRows = rows.sorted { $0.occurredAt < $1.occurredAt }

        for row in sortedRows {
            var best: (txn: Txn, gap: Int)?

            for txn in live where !used.contains(txn.id) {
                guard txn.amountMinor == row.amountMinor else { continue }
                let txnIsIncome = txn.type == .income
                guard txnIsIncome == row.isIncome else { continue }
                let gap = abs(calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: txn.occurredAt),
                    to: calendar.startOfDay(for: row.occurredAt)
                ).day ?? 99)
                guard gap <= windowDays else { continue }
                if let current = best {
                    if gap < current.gap {
                        best = (txn, gap)
                    }
                } else {
                    best = (txn, gap)
                }
            }

            if let best {
                used.insert(best.txn.id)
                matched += 1
            } else {
                missing.append(row)
            }
        }

        // 只在文件覆盖的时间范围内判断「多记」，否则会把历史全算进来
        var extra: [Txn] = []
        if let first = sortedRows.first?.occurredAt, let last = sortedRows.last?.occurredAt {
            let lower = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: first)) ?? first
            let upper = calendar.date(byAdding: .day, value: windowDays + 1, to: calendar.startOfDay(for: last)) ?? last
            extra = live.filter { txn in
                !used.contains(txn.id) && txn.occurredAt >= lower && txn.occurredAt < upper
            }
        }

        return BillCompareResult(
            totalRows: rows.count,
            matchedCount: matched,
            missing: missing,
            extra: extra
        )
    }
}
