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
        // 回看历史月份时，「近 90 天」「超过 45 天」都应以该月月末为基准，
        // 否则 5 月的报告会用今天的数据算均值、算超期。
        let referenceDate = min(Date(), thisRange.end.addingTimeInterval(-0.001))

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

        // 2. 单笔异常：超过该分类前 90 天单笔均值的 3 倍
        let recentStart = calendar.date(byAdding: .day, value: -90, to: referenceDate) ?? referenceDate
        let recent = live.filter { $0.occurredAt >= recentStart && $0.occurredAt < referenceDate && $0.type == .expense && $0.source != .reimbursement }

        var categoryAverage: [UUID: Int64] = [:]
        var categoryCount: [UUID: Int] = [:]
        for txn in recent {
            guard let categoryId = txn.categoryId else { continue }
            categoryAverage[categoryId, default: 0] += txn.amountMinor
            categoryCount[categoryId, default: 0] += 1
        }

        var outliers: [(txn: Txn, ratio: Double)] = []
        for txn in live where txn.type == .expense && txn.source != .reimbursement && thisRange.contains(txn.occurredAt) {
            guard let categoryId = txn.categoryId,
                  let count = categoryCount[categoryId], count >= 3,
                  let total = categoryAverage[categoryId] else { continue }
            let average = total / Int64(count)
            guard average > 0, txn.amountMinor >= average * 3, txn.amountMinor >= 30_000 else { continue }
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

        // 3. 订阅识别：同一备注在 3 个以上不同月份出现，且金额稳定、频率接近每月一次。
        //    只按「同备注」判断会把「午饭」「打车」这类日常备注误报成订阅。
        var noteMonths: [String: Set<String>] = [:]
        var noteAmounts: [String: [Int64]] = [:]
        for txn in live where txn.type == .expense && txn.source != .reimbursement && txn.occurredAt < nextStart {
            guard let rawNote = txn.note?.trimmingCharacters(in: .whitespacesAndNewlines), rawNote.count >= 2 else { continue }
            noteMonths[rawNote, default: []].insert(AppCalendar.monthKey(txn.occurredAt))
            noteAmounts[rawNote, default: []].append(txn.amountMinor)
        }
        let subscription = noteMonths
            .filter { element in
                let key = element.key
                guard element.value.count >= 3, let amounts = noteAmounts[key], !amounts.isEmpty else { return false }
                guard let minAmount = amounts.min(), let maxAmount = amounts.max(), minAmount > 0 else { return false }
                // 金额波动不超过 20%，且平均每月不超过 2 次，才像固定订阅
                let stable = Double(maxAmount) / Double(minAmount) <= 1.2
                let frequency = Double(amounts.count) / Double(element.value.count) <= 2
                return stable && frequency
            }
            .max { $0.value.count < $1.value.count }
        if let subscription {
            let months = subscription.value.count
            results.append(
                Insight(
                    id: "subscription-\(subscription.key)",
                    title: "可能是固定订阅：\(subscription.key)",
                    detail: "已连续 \(months) 个月出现，金额基本不变，可考虑是否还需要",
                    symbol: "arrow.triangle.2.circlepath",
                    level: .info
                )
            )
        }

        // 4. 待报销超期
        let threshold = calendar.date(byAdding: .day, value: -45, to: referenceDate) ?? referenceDate
        let overdue = live.filter { txn in
            guard txn.type == .expense, txn.isReimbursable, txn.occurredAt < threshold else { return false }
            guard let claimId = txn.claimId, let claim = claims.first(where: { $0.id == claimId && $0.deletedAt == nil }) else { return true }
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

        // 5. 储蓄率：沿用现金流口径，退款冲减支出且不计收入。
        let summary = StatsEngine.summary(range: thisRange, caliber: .cashFlow, txns: live, claims: claims)
        let income = summary.incomeMinor
        let expense = summary.expenseMinor
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
        for txn in txns where txn.type == .expense && txn.source != .reimbursement && range.contains(txn.occurredAt) {
            guard let categoryId = txn.categoryId else { continue }
            result[categoryId, default: 0] += txn.amountMinor
        }
        for txn in txns where RefundService.isRefund(txn) && range.contains(txn.occurredAt) {
            // 与统计页一致：退款冲减「原支出」的分类，而不是退款流水自己后来改过的分类
            let originalCategory = txn.refundOfTxnId.flatMap { id in
                txns.first(where: { $0.id == id && $0.deletedAt == nil })?.categoryId
            }
            guard let categoryId = originalCategory ?? txn.categoryId else { continue }
            result[categoryId, default: 0] -= txn.amountMinor
        }
        return result
    }
}
