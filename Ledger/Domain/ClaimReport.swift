import Foundation

struct ClaimReportClaim: Identifiable {
    let id: UUID
    let title: String
    let count: Int
    let totalMinor: Int64
    let status: ClaimStatus
    let submittedAt: Date?
    let reimbursedAt: Date?

    /// 回款天数（提交 → 到账）
    var days: Int? {
        guard let submittedAt, let reimbursedAt else { return nil }
        return AppCalendar.gregorian.dateComponents([.day], from: submittedAt, to: reimbursedAt).day
    }
}

struct ClaimMonthlyReport {
    let monthKey: String
    let advanceCount: Int
    let advanceMinor: Int64
    let submittedMinor: Int64
    let receivedMinor: Int64
    let outstandingMinor: Int64
    let categoryTotals: [(name: String, amountMinor: Int64)]
    let claims: [ClaimReportClaim]
    let overdueItems: [Txn]
    let averageDays: Int?

    var hasData: Bool {
        advanceCount > 0 || !claims.isEmpty
    }
}

enum ClaimReportBuilder {
    static func build(
        monthAnchor: Date,
        claims: [Claim],
        txns: [Txn],
        categories: [Category]
    ) -> ClaimMonthlyReport {
        let monthKey = AppCalendar.monthKey(monthAnchor)
        let interval = AppCalendar.monthInterval(containing: monthAnchor)

        let liveClaims = claims.filter { $0.deletedAt == nil }
        let liveTxns = txns.filter { $0.deletedAt == nil }

        // 本月新增垫付
        let advances = liveTxns.filter {
            $0.type == .expense && $0.isReimbursable && interval.contains($0.occurredAt)
        }
        let advanceMinor = advances.reduce(Int64(0)) { $0 + $1.amountMinor }

        // 本月报销单
        let monthClaims = liveClaims.filter { $0.periodMonth == monthKey }
        let submittedMinor = monthClaims
            .filter { $0.submittedAt != nil || $0.status != .draft }
            .reduce(Int64(0)) { partial, claim in
                partial + liveTxns.filter { $0.claimId == claim.id && $0.type == .expense && $0.isReimbursable }
                    .reduce(Int64(0)) { $0 + $1.amountMinor }
            }
        let receivedMinor = monthClaims.compactMap { $0.receivedAmountMinor }.reduce(Int64(0), +)

        // 月末未到账：所有仍未核销的报销单
        let outstandingMinor = liveClaims
            .filter { $0.status == .draft || $0.status == .submitted }
            .reduce(Int64(0)) { partial, claim in
                let total = liveTxns.filter { $0.claimId == claim.id && $0.type == .expense && $0.isReimbursable }
                    .reduce(Int64(0)) { $0 + $1.amountMinor }
                let received = claim.receivedAmountMinor ?? 0
                return partial + max(0, total - received)
            }

        // 分类小计
        var totals: [UUID: Int64] = [:]
        var unknown: Int64 = 0
        for txn in advances {
            if let categoryId = txn.categoryId {
                totals[categoryId, default: 0] += txn.amountMinor
            } else {
                unknown += txn.amountMinor
            }
        }
        var categoryTotals: [(String, Int64)] = totals.map { pair in
            (categories.first { $0.id == pair.key }?.name ?? "未分类", pair.value)
        }
        if unknown > 0 {
            categoryTotals.append(("未分类", unknown))
        }
        categoryTotals.sort { $0.1 > $1.1 }

        // 明细
        let claimSummaries: [ClaimReportClaim] = monthClaims
            .map { claim in
                let items = liveTxns.filter { $0.claimId == claim.id && $0.type == .expense && $0.isReimbursable }
                return ClaimReportClaim(
                    id: claim.id,
                    title: claim.title,
                    count: items.count,
                    totalMinor: items.reduce(Int64(0)) { $0 + $1.amountMinor },
                    status: claim.status,
                    submittedAt: claim.submittedAt,
                    reimbursedAt: claim.reimbursedAt
                )
            }
            .sorted { $0.totalMinor > $1.totalMinor }

        // 超期：垫付超过 45 天仍未提交
        let threshold = AppCalendar.gregorian.date(byAdding: .day, value: -45, to: Date()) ?? Date()
        let overdueItems = liveTxns.filter { txn in
            guard txn.type == .expense, txn.isReimbursable, txn.occurredAt < threshold else { return false }
            guard let claimId = txn.claimId, let claim = liveClaims.first(where: { $0.id == claimId }) else { return true }
            return claim.status == .draft
        }

        let days = claimSummaries.compactMap { $0.days }
        let averageDays = days.isEmpty ? nil : days.reduce(0, +) / days.count

        return ClaimMonthlyReport(
            monthKey: monthKey,
            advanceCount: advances.count,
            advanceMinor: advanceMinor,
            submittedMinor: submittedMinor,
            receivedMinor: receivedMinor,
            outstandingMinor: outstandingMinor,
            categoryTotals: categoryTotals,
            claims: claimSummaries,
            overdueItems: overdueItems,
            averageDays: averageDays
        )
    }

    static func csv(_ report: ClaimMonthlyReport) -> String {
        func field(_ value: String) -> String {
            if value.contains(",") || value.contains("\"") || value.contains("\n") {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return value
        }

        var lines: [String] = []
        lines.append("报销月报,\(report.monthKey)")
        lines.append("")
        lines.append("项目,数值")
        lines.append("本月垫付笔数,\(report.advanceCount)")
        lines.append("本月垫付金额,\(Money.formatPlain(report.advanceMinor))")
        lines.append("已提交金额,\(Money.formatPlain(report.submittedMinor))")
        lines.append("已到账金额,\(Money.formatPlain(report.receivedMinor))")
        lines.append("未到账余额,\(Money.formatPlain(report.outstandingMinor))")
        if let averageDays = report.averageDays {
            lines.append("平均回款天数,\(averageDays)")
        }
        lines.append("")

        if !report.categoryTotals.isEmpty {
            lines.append("按分类小计")
            lines.append("分类,金额")
            for item in report.categoryTotals {
                lines.append("\(field(item.0)),\(Money.formatPlain(item.1))")
            }
            lines.append("")
        }

        if !report.claims.isEmpty {
            lines.append("报销单明细")
            lines.append("标题,笔数,合计,状态,提交日,到账日,回款天数")
            for claim in report.claims {
                let submitted = claim.submittedAt.map { DateFormatter.ledgerShort.string(from: $0) } ?? ""
                let reimbursed = claim.reimbursedAt.map { DateFormatter.ledgerShort.string(from: $0) } ?? ""
                lines.append([
                    field(claim.title),
                    "\(claim.count)",
                    Money.formatPlain(claim.totalMinor),
                    claim.status.displayName,
                    submitted,
                    reimbursed,
                    claim.days.map(String.init) ?? ""
                ].joined(separator: ","))
            }
            lines.append("")
        }

        if !report.overdueItems.isEmpty {
            lines.append("超期未提交（>45 天）")
            lines.append("日期,金额,备注")
            for txn in report.overdueItems {
                lines.append([
                    DateFormatter.ledgerShort.string(from: txn.occurredAt),
                    Money.formatPlain(txn.amountMinor),
                    field(txn.note ?? "")
                ].joined(separator: ","))
            }
        }

        return lines.joined(separator: "\n")
    }
}
