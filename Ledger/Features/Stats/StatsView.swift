import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var claims: [Claim]
    @Query private var categories: [Category]

    @State private var monthAnchor = Date()
    @State private var caliber: StatsCaliber = .personal

    private var liveTxns: [Txn] { allTxns.filter { $0.deletedAt == nil } }
    private var interval: DateInterval { AppCalendar.monthInterval(containing: monthAnchor) }

    private var summary: StatsSummary {
        StatsEngine.summary(range: interval, caliber: caliber, txns: liveTxns, claims: claims)
    }

    private var slices: [CategorySlice] {
        StatsEngine.byCategory(
            range: interval,
            caliber: caliber,
            txns: liveTxns,
            claims: claims,
            categories: categories
        )
    }

    private var buckets: [MonthBucket] {
        StatsEngine.byMonth(months: 6, endingAt: monthAnchor, txns: liveTxns)
    }

    private var totalExpense: Int64 {
        slices.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    monthSwitcher
                    caliberPicker
                    caliberHint
                    summaryCard
                    donutSection
                    rankSection
                    trendSection
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.pageBackground)
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle)
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.s)
    }

    private var caliberPicker: some View {
        Picker("口径", selection: $caliber) {
            ForEach(StatsCaliber.allCases) { item in
                Text(item.displayName).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var caliberHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caliberDescription)
            if caliber == .personal && summary.pendingMinor == 0 && summary.expenseMinor > 0 {
                Text("本月没有待报销记录，所以这个口径与「现金流」结果相同。")
                    .foregroundStyle(.secondary)
            }
            if caliber == .personal && summary.pendingMinor > 0 {
                Text("已剔除待报销 \(Money.format(summary.pendingMinor))")
                    .foregroundStyle(Theme.warning)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var caliberDescription: String {
        switch caliber {
        case .cashFlow:
            return "所有收支都计入，反映账户里钱的实际进出。"
        case .personal:
            return "垫付中的报销不算你花的，报销到账也不算收入——看你自己真正花掉多少。"
        case .advance:
            return "只看标记为「可报销」的垫付与对应到账，用来核对报销。"
        }
    }

    private var summaryCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack {
                metric(title: "支出", value: Money.format(summary.expenseMinor), color: .primary)
                Divider().frame(height: 28)
                metric(title: "收入", value: Money.format(summary.incomeMinor), color: Theme.income)
                Divider().frame(height: 28)
                metric(title: "结余", value: Money.format(summary.balanceMinor), color: .primary)
            }
            if summary.pendingMinor > 0 {
                HStack {
                    Text("待报销")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.format(summary.pendingMinor))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var donutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("支出构成")
                .font(.subheadline.weight(.semibold))

            if slices.isEmpty {
                emptyHint
            } else {
                Chart(slices.prefix(8).map { $0 }, id: \.id) { slice in
                    SectorMark(
                        angle: .value("金额", slice.amountMinor),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hexString: slice.colorHex))
                }
                .frame(height: 170)
                .overlay {
                    VStack(spacing: 2) {
                        Text("合计").font(.caption2).foregroundStyle(.secondary)
                        Text(Money.format(totalExpense))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }

                legendGrid
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// 环形图图例：颜色 + 分类名 + 占比
    private var legendGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
            ForEach(slices.prefix(8), id: \.id) { slice in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hexString: slice.colorHex))
                        .frame(width: 8, height: 8)
                    Text(slice.name)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(String(format: "%.0f%%", percent(of: slice)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func percent(of slice: CategorySlice) -> Double {
        guard totalExpense > 0 else { return 0 }
        return Double(slice.amountMinor) / Double(totalExpense) * 100
    }

    private var rankSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("分类排行")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("点击查看明细")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if slices.isEmpty {
                emptyHint
            } else {
                ForEach(slices.prefix(10), id: \.id) { slice in
                    NavigationLink {
                        CategoryTxnListView(categoryId: slice.id, range: interval, title: slice.name)
                    } label: {
                        rankRow(slice)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func rankRow(_ slice: CategorySlice) -> some View {
        let ratio = totalExpense > 0 ? Double(slice.amountMinor) / Double(totalExpense) : 0
        return HStack(spacing: Theme.Spacing.m) {
            Text(slice.emoji)
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
                .background(Color(hexString: slice.colorHex).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(slice.name).font(.subheadline)
                    Spacer()
                    Text(Money.format(slice.amountMinor)).font(.subheadline).monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.secondarySystemBackground))
                        Capsule()
                            .fill(Color(hexString: slice.colorHex))
                            .frame(width: max(2, geo.size.width * ratio))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text("\(slice.count) 笔")
                    Spacer()
                    Text(String(format: "%.0f%%", ratio * 100))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("近 6 个月支出")
                .font(.subheadline.weight(.semibold))

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("月份", String(bucket.id.suffix(2)) + "月"),
                    y: .value("支出", Double(bucket.expenseMinor) / 100.0)
                )
                .foregroundStyle(Theme.accent.opacity(0.85))
                .cornerRadius(4)
            }
            .frame(height: 160)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var emptyHint: some View {
        Text("本月还没有支出记录")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.l)
    }

    private var monthTitle: String {
        let comps = AppCalendar.gregorian.dateComponents([.year, .month], from: monthAnchor)
        return "\(comps.year ?? 0)年\(comps.month ?? 0)月"
    }

    private func shiftMonth(_ delta: Int) {
        if let next = AppCalendar.gregorian.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
        }
    }
}
