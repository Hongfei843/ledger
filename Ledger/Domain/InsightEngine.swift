import Foundation

enum InsightLevel {
    case info
    case warning
    case positive
}

struct Insight: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let level: InsightLevel
}

/// 纯本地规则引擎：不联网、可解释、可测试。
/// 每条洞察都必须带具体数字，避免"正确的废话"。
enum InsightEngine {
    static func generate(
        monthAnchor: Date,
        txns: [Txn],
        categories: [Category],
        claims: [Claim],
        limit: Int = 4
    ) -> [Insight] {
        let live = txns.filter { $0.deletedAt == nil }
        let calendar = AppCalendar.gregorian
        let thisStart = AppCalendar.startOfMonth(monthAnchor)
        let nextStart = AppCalendar.startOfNextMonth(monthAnchor)
        let thisRange = DateInterval(start: thisStart, end: nextStart)

        guard let prevStart = calendar.date(byAdding: .month, value: -1, to: thisStart) else { return [] }
        let prevRange = DateInterval(start: prevStart, end: thisStart)

        var results: [Insight] = []

        // 1. 分类环比异常
        let thisByCategory = totals(in: thisRange, txns: live)
        let prevByCategory = totals(in: prevRange, txns: live)

        var jumps: [(name: String, delta: Int64, ratio: Double)] = []
        for (categoryId, amount) in thisByCategory {
            let previous = prevByCategory[categoryId] ?? 0
            guard previous > 0, amount > previous else { continue }
            let delta = amount - previous
            let ratio = Double(delta) / Double(previous)
            guard delta > 20_000, ratio > 0.5 else { continue }
            let name = categories.first { $0.id == categoryId }?.name ?? "未分类"
            jumps.append((name, delta, ratio))
        }
        jumps.sort { $0.delta > $1.delta }
        for jump in jumps.prefix(1) {
            results.append(
                Insight(
                    id: "jump-\(jump.name)",
                    title: "\(jump.name)涨了 \(Int(jump.ratio * 100))%",
                    detail: "比上月多花 \(Money.format(jump.delta))",
                    symbol: "arrow.up.right",
                    level: .warning
                )
            )
        }

        // 2. 单笔异常：超过该分类近 90 天单笔均值的 3 倍
        let recentStart = calendar.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let recent = live.filter { $0.occurredAt >= recentStart && $0.type == .expense }

        var categoryAverage: [UUID: Int64] = [:]
        var categoryCount: [UUID: Int] = [:]
        for txn in recent {
            guard let categoryId = txn.categoryId else { continue }
            categoryAverage[categoryId, default: 0] += txn.amountMinor
            categoryCount[categoryId, default: 0] += 1
        }

        var outliers: [(txn: Txn, ratio: Double)] = []
        for txn in live where txn.type == .expense && thisRange.contains(txn.occurredAt) {
            guard let categoryId = txn.categoryId,
                  let count = categoryCount[categoryId], count >= 3,
                  let total = categoryAverage[categoryId] else { continue }
            let average = total / Int64(count)
            guard average > 0, txn.amountMinor > average * 3, txn.amountMinor > 30_000 else { continue }
            outliers.append((txn, Double(txn.amountMinor) / Double(average)))
        }
        outliers.sort { $0.txn.amountMinor > $1.txn.amountMinor }
        if let outlier = outliers.first {
            let name = categories.first { $0.id == outlier.txn.categoryId }?.name ?? "该分类"
            results.append(
                Insight(
                    id: "outlier-\(outlier.txn.id.uuidString)",
                    title: "一笔\(name)明显偏高",
                    detail: "\(Money.format(outlier.txn.amountMinor))，是近期平均的 \(String(format: "%.1f", outlier.ratio)) 倍",
                    symbol: "exclamationmark.triangle",
                    level: .warning
                )
            )
        }

        // 3. 订阅识别：同一备注在 3 个以上不同月份出现
        var monthsByNote: [String: Set<String>] = [:]
        for txn in live where txn.type == .expense {
            guard let note = txn.note, note.count >= 2 else { continue }
            monthsByNote[note, default: []].insert(AppCalendar.monthKey(txn.occurredAt))
        }
        if let subscription = monthsByNote
            .filter({ $0.value.count >= 3 })
            .max(by: { $0.value.count < $1.value.count }) {
            results.append(
                Insight(
                    id: "subscription-\(subscription.key)",
                    title: "可能是固定订阅：\(subscription.key)",
                    detail: "已连续 \(subscription.value.count) 个月出现，可考虑是否还需要",
                    symbol: "arrow.triangle.2.circlepath",
                    level: .info
                )
            )
        }

        // 4. 待报销超期
        let threshold = calendar.date(byAdding: .day, value: -45, to: Date()) ?? Date()
        let overdue = live.filter { txn in
            guard txn.type == .expense, txn.isReimbursable, txn.occurredAt < threshold else { return false }
            guard let claimId = txn.claimId, let claim = claims.first(where: { $0.id == claimId }) else { return true }
            return claim.status == .draft
        }
        if !overdue.isEmpty {
            let total = overdue.reduce(Int64(0)) { $0 + $1.amountMinor }
            results.append(
                Insight(
                    id: "overdue-claim",
                    title: "有垫付超过 45 天没提交",
                    detail: "\(overdue.count) 笔，合计 \(Money.format(total))",
                    symbol: "clock.badge.exclamationmark",
                    level: .warning
                )
            )
        }

        // 5. 储蓄率
        var income: Int64 = 0
        var expense: Int64 = 0
        for txn in live where thisRange.contains(txn.occurredAt) {
            if txn.type == .income { income += txn.amountMinor }
            if txn.type == .expense { expense += txn.amountMinor }
        }
        if income > 0 {
            let rate = Double(income - expense) / Double(income)
            if rate < 0.1 {
                results.append(
                    Insight(
                        id: "saving-rate-low",
                        title: "本月几乎没存下钱",
                        detail: "储蓄率 \(String(format: "%.0f%%", rate * 100))，收入 \(Money.format(income))、支出 \(Money.format(expense))",
                        symbol: "chart.line.downtrend.xyaxis",
                        level: .warning
                    )
                )
            } else if rate > 0.3 {
                results.append(
                    Insight(
                        id: "saving-rate-good",
                        title: "本月储蓄率 \(String(format: "%.0f%%", rate * 100))",
                        detail: "存下 \(Money.format(income - expense))，保持住",
                        symbol: "checkmark.seal",
                        level: .positive
                    )
                )
            }
        }

        let priority: [InsightLevel: Int] = [.warning: 0, .positive: 1, .info: 2]
        return results
            .sorted { (priority[$0.level] ?? 9) < (priority[$1.level] ?? 9) }
            .prefix(limit)
            .map { $0 }
    }

    private static func totals(in range: DateInterval, txns: [Txn]) -> [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for txn in txns where txn.type == .expense && range.contains(txn.occurredAt) {
            guard let categoryId = txn.categoryId else { continue }
            result[categoryId, default: 0] += txn.amountMinor
        }
        return result
    }
}
