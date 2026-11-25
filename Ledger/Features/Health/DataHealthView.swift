import SwiftUI
import SwiftData

/// 数据健康度：一眼看出账本哪里不可信。
struct DataHealthView: View {
    @Query private var allTxns: [Txn]
    @Query private var accounts: [Account]
    @Query private var claims: [Claim]
    @Query private var statements: [Statement]

    private var liveTxns: [Txn] { allTxns.filter { $0.deletedAt == nil } }
    private var liveAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
    }

    struct Issue: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let level: InsightLevel
        let route: Route?

        enum Route { case reconciliation, reimbursement, accounts, categories, duplicates }
    }

    private var uncategorized: [Txn] {
        liveTxns.filter { $0.categoryId == nil }
    }

    private var unclassifiedRatio: Double {
        guard !liveTxns.isEmpty else { return 0 }
        return Double(uncategorized.count) / Double(liveTxns.count)
    }

    private var staleAccounts: [Account] {
        let threshold = AppCalendar.gregorian.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let activeIds = Set(liveTxns.flatMap { [$0.accountId, $0.counterAccountId].compactMap { $0 } })
        return liveAccounts.filter {
            ($0.lastReconciledAt ?? .distantPast) < threshold
                && (activeIds.contains($0.id) || $0.openingBalanceMinor != 0)
        }
    }

    private var overdueClaims: [Txn] {
        let threshold = AppCalendar.gregorian.date(byAdding: .day, value: -45, to: Date()) ?? Date()
        return liveTxns.filter { txn in
            guard txn.type == .expense, txn.isReimbursable, txn.occurredAt < threshold else { return false }
            guard let claimId = txn.claimId, let claim = claims.first(where: { $0.id == claimId }) else { return true }
            return claim.status == .draft
        }
    }

    private var openStatements: [Statement] {
        statements.filter { $0.deletedAt == nil && !$0.isSettled }
    }

    private var withoutNoteRatio: Double {
        guard !liveTxns.isEmpty else { return 0 }
        let empty = liveTxns.filter { ($0.note ?? "").isEmpty }.count
        return Double(empty) / Double(liveTxns.count)
    }

    /// 疑似重复：同一天 + 同金额 + 同账户 + 同备注
    private var duplicateGroups: [[Txn]] {
        var buckets: [String: [Txn]] = [:]
        for txn in liveTxns {
            let day = AppCalendar.startOfDay(txn.occurredAt).timeIntervalSince1970
            let key = "\(Int(day))|\(txn.amountMinor)|\(txn.accountId.uuidString)|\(txn.note ?? "")"
            buckets[key, default: []].append(txn)
        }
        return buckets.values.filter { $0.count > 1 }
    }

    private var issues: [Issue] {
        var result: [Issue] = []

        if !staleAccounts.isEmpty {
            result.append(Issue(
                id: "stale",
                title: "\(staleAccounts.count) 个账户超过 30 天未对账",
                detail: "账面可能已经和银行实际对不上，建议逐账户核对一次",
                symbol: "arrow.triangle.2.circlepath",
                level: .warning,
                route: .reconciliation
            ))
        }

        if !overdueClaims.isEmpty {
            let total = overdueClaims.reduce(Int64(0)) { $0 + $1.amountMinor }
            result.append(Issue(
                id: "claim",
                title: "\(overdueClaims.count) 笔垫付超过 45 天未提交",
                detail: "合计 \(Money.format(total))，越拖越难报",
                symbol: "clock.badge.exclamationmark",
                level: .warning,
                route: .reimbursement
            ))
        }

        if !openStatements.isEmpty {
            let total = openStatements.reduce(Int64(0)) { $0 + $1.outstandingMinor }
            result.append(Issue(
                id: "statement",
                title: "\(openStatements.count) 张信用卡账单未结清",
                detail: "待还合计 \(Money.format(total))",
                symbol: "creditcard",
                level: .warning,
                route: .accounts
            ))
        }

        if unclassifiedRatio > 0.05 {
            result.append(Issue(
                id: "uncategorized",
                title: "\(uncategorized.count) 笔流水没有分类",
                detail: "占全部记录 \(String(format: "%.0f%%", unclassifiedRatio * 100))，会让统计失真",
                symbol: "questionmark.circle",
                level: .info,
                route: .categories
            ))
        }

        if !duplicateGroups.isEmpty {
            result.append(Issue(
                id: "duplicate",
                title: "\(duplicateGroups.count) 组疑似重复记录",
                detail: "同一天、同金额、同账户、同备注出现多次，可能是重复记账",
                symbol: "doc.on.doc",
                level: .info,
                route: .duplicates
            ))
        }

        if withoutNoteRatio > 0.5 && liveTxns.count > 20 {
            result.append(Issue(
                id: "note",
                title: "过半记录没有备注",
                detail: "备注是日后回忆和 AI 分析的关键，建议至少写个关键词",
                symbol: "text.alignleft",
                level: .info,
                route: nil
            ))
        }

        if result.isEmpty && !liveTxns.isEmpty {
            result.append(Issue(
                id: "ok",
                title: "账本状态良好",
                detail: "没有发现未对账、超期报销或疑似重复的问题",
                symbol: "checkmark.seal",
                level: .positive,
                route: nil
            ))
        }

        return result
    }

    /// 健康分：100 起扣
    private var score: Int {
        var value = 100
        if !staleAccounts.isEmpty { value -= min(30, staleAccounts.count * 10) }
        if !overdueClaims.isEmpty { value -= 15 }
        if !openStatements.isEmpty { value -= 10 }
        if unclassifiedRatio > 0.05 { value -= Int(min(25, unclassifiedRatio * 100)) }
        if !duplicateGroups.isEmpty { value -= 5 }
        return max(0, value)
    }

    private var scoreColor: Color {
        if score >= 85 { return Theme.income }
        if score >= 60 { return Theme.warning }
        return Theme.danger
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.l) {
                    ZStack {
                        Circle()
                            .stroke(Color(.secondarySystemBackground), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(score) / 100)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(score)")
                            .font(Theme.Fonts.amountL)
                            .monospacedDigit()
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("账本健康度")
                            .font(.subheadline.weight(.semibold))
                        Text(summaryText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            ForEach(issues) { issue in
                issueRow(issue)
            }
        }
        .navigationTitle("数据健康")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryText: String {
        "\(liveTxns.count) 条流水 · \(liveAccounts.count) 个账户 · \(String(format: "%.0f%%", unclassifiedRatio * 100)) 未分类"
    }

    private func issueRow(_ issue: Issue) -> some View {
        Group {
            if let route = issue.route {
                NavigationLink {
                    destination(route)
                } label: {
                    content(issue)
                }
            } else {
                content(issue)
            }
        }
    }

    private func content(_ issue: Issue) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: issue.symbol)
                .font(.system(size: 15))
                .foregroundStyle(color(issue.level))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(issue.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func color(_ level: InsightLevel) -> Color {
        switch level {
        case .warning: return Theme.warning
        case .positive: return Theme.income
        case .info: return Theme.accent
        }
    }

    @ViewBuilder
    private func destination(_ route: Issue.Route) -> some View {
        switch route {
        case .reconciliation:
            ReconciliationView()
        case .reimbursement:
            ClaimListView()
        case .accounts:
            AccountsView()
        case .categories:
            CategoryManageView()
        case .duplicates:
            DuplicateReviewView()
        }
    }
}
