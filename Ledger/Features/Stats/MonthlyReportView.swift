import SwiftUI
import SwiftData
import Charts

/// 月度报告：收入/支出/结余、环比、储蓄率、分类排行、每日趋势、大额支出。
struct MonthlyReportView: View {
    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var categories: [Category]

    @State private var monthAnchor: Date

    init(month: Date) {
        _monthAnchor = State(initialValue: month)
    }

    private var liveTxns: [Txn] { allTxns.filter { $0.deletedAt == nil } }

    private var report: MonthlyReport {
        MonthlyReportBuilder.build(monthAnchor: monthAnchor, txns: liveTxns, categories: categories)
    }

    var body: some View {
        let report = report
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                monthSwitcher
                summaryCard(report)
                if report.hasData {
                    savingsCard(report)
                    categorySection(report)
                    trendSection(report)
                    topExpensesSection(report)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.pageBackground)
        .navigationTitle("月度报告")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(report)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(!report.hasData)
                .accessibilityLabel("分享月报")
            }
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(monthTitle)
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func summaryCard(_ report: MonthlyReport) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                summaryTile(title: "收入", amount: report.incomeMinor, color: Theme.income, change: report.incomeChangePercent)
                summaryTile(title: "支出", amount: report.expenseMinor, color: .primary, change: report.expenseChangePercent)
            }
            HStack {
                Text("结余")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Money.format(report.netMinor))
                    .font(Theme.Fonts.amountM)
                    .monospacedDigit()
                    .foregroundStyle(report.netMinor < 0 ? Theme.danger : .primary)
            }
            Divider()
            HStack {
                Label("\(report.txnsCount) 笔流水", systemImage: "list.bullet")
                Spacer()
                if let rate = report.savingsRatePercent {
                    Label("储蓄率 \(rate)%", systemImage: "percent")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func summaryTile(title: String, amount: Int64, color: Color, change: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Money.format(amount))
                .font(Theme.Fonts.amountM)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let change {
                Text(change >= 0 ? "较上月 +\(change)%" : "较上月 \(change)%")
                    .font(.system(size: 10))
                    .foregroundStyle(change >= 0 ? Theme.income : Theme.danger)
            } else {
                Text("上月无数据")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func savingsCard(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("一句话总结")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(summaryLine(report))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func categorySection(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("钱花在哪")
                .font(.headline)
            ForEach(report.categories) { category in
                HStack(spacing: Theme.Spacing.s) {
                    Text(category.emoji)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(category.name).font(.subheadline)
                            Spacer()
                            Text(Money.format(category.amountMinor))
                                .font(.subheadline)
                                .monospacedDigit()
                            Text("\(Int((category.share * 100).rounded()))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule()
                                    .fill(Color(hexString: category.colorHex))
                                    .frame(width: max(4, proxy.size.width * category.share))
                            }
                        }
                        .frame(height: 5)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func trendSection(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("每日支出")
                .font(.headline)
            Chart(report.days) { day in
                BarMark(
                    x: .value("日期", day.day, unit: .day),
                    y: .value("支出", Double(day.expenseMinor) / 100)
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .frame(height: 130)
        }
        .padding(Theme.Spacing.m)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func topExpensesSection(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("本月最大几笔")
                .font(.headline)
            ForEach(report.topExpenses) { item in
                HStack(spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.payee)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("\(item.categoryName) · \(DateFormatter.ledgerShort.string(from: item.occurredAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Money.format(item.amountMinor))
                        .font(.subheadline)
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("这个月还没有流水")
                .font(.subheadline)
            Text("记几笔之后，这里会自动生成报告")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .cardStyle()
    }

    // MARK: - 文本

    private func summaryLine(_ report: MonthlyReport) -> String {
        var parts: [String] = []
        parts.append("这个月收入 \(Money.format(report.incomeMinor))，支出 \(Money.format(report.expenseMinor))")
        if report.netMinor >= 0 {
            parts.append("结余 \(Money.format(report.netMinor))")
        } else {
            parts.append("超支 \(Money.format(-report.netMinor))")
        }
        if let rate = report.savingsRatePercent {
            parts.append("储蓄率 \(rate)%")
        }
        if let change = report.expenseChangePercent {
            parts.append(change >= 0 ? "支出比上月多 \(change)%" : "支出比上月少 \(abs(change))%")
        }
        if let top = report.categories.first {
            parts.append("花得最多的是\(top.name)")
        }
        return parts.joined(separator: "，") + "。"
    }

    private func shareText(_ report: MonthlyReport) -> String {
        guard report.hasData else { return "轻账月报：这个月还没有流水。" }
        var lines: [String] = []
        lines.append("【轻账月报】\(monthTitle)")
        lines.append("")
        lines.append(summaryLine(report))
        lines.append("")
        if !report.categories.isEmpty {
            lines.append("分类排行：")
            for category in report.categories.prefix(5) {
                lines.append("- \(category.emoji) \(category.name) \(Money.format(category.amountMinor))（\(Int((category.share * 100).rounded()))%）")
            }
            lines.append("")
        }
        if !report.topExpenses.isEmpty {
            lines.append("最大几笔：")
            for item in report.topExpenses {
                lines.append("- \(item.payee) \(Money.format(item.amountMinor))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 月份

    private var monthTitle: String {
        let comps = AppCalendar.gregorian.dateComponents([.year, .month], from: monthAnchor)
        return "\(comps.year ?? 0)年\(comps.month ?? 0)月"
    }

    private var isCurrentMonth: Bool {
        AppCalendar.gregorian.isDate(monthAnchor, equalTo: Date(), toGranularity: .month)
    }

    private func shiftMonth(_ delta: Int) {
        monthAnchor = AppCalendar.gregorian.date(byAdding: .month, value: delta, to: monthAnchor) ?? monthAnchor
        Haptics.selection()
    }
}
