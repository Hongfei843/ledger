import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var claims: [Claim]
    @Query private var categories: [Category]
    @AppStorage(BookScope.key) private var currentBookRaw = ""

    @State private var monthAnchor = Date()
    @State private var caliber: StatsCaliber = .personal

    private func bookMatches(_ id: UUID) -> Bool { BookScope.matches(id, raw: currentBookRaw) }
    private var liveTxns: [Txn] { allTxns.filter { $0.deletedAt == nil && bookMatches($0.bookId) } }
    private var liveClaims: [Claim] { claims.filter { $0.deletedAt == nil && bookMatches($0.bookId) } }
    private var scopedCategories: [Category] { categories.filter { bookMatches($0.bookId) } }
    private var interval: DateInterval { AppCalendar.monthInterval(containing: monthAnchor) }

    private var summary: StatsSummary {
        StatsEngine.summary(range: interval, caliber: caliber, txns: liveTxns, claims: liveClaims)
    }

    private var breakdown: CategoryBreakdown {
        StatsEngine.breakdown(
            range: interval,
            caliber: caliber,
            txns: liveTxns,
            claims: liveClaims,
            categories: scopedCategories
        )
    }

    private var slices: [CategorySlice] { breakdown.slices }

    private var buckets: [MonthBucket] {
        StatsEngine.byMonth(months: 6, endingAt: monthAnchor, txns: liveTxns, claims: liveClaims, caliber: caliber)
    }

    /// 主卡净支出是唯一口径：环形图、排行、下钻都按它算占比；
    /// 未能落到分类上的退款冲减由 `breakdown.refundOffsetMinor` 单列说明。
    private var totalExpense: Int64 { summary.expenseMinor }

    /// 占比分母：正常等于净支出；当退款把某个分类冲成负数（分类合计反而大于净支出）时，
    /// 改用分类合计做分母，保证占比不会出现 300% 这种结果。
    private var percentBase: Int64 { max(totalExpense, breakdown.sliceTotalMinor) }

    /// 环形图最多画 8 块，其余合并为「其他 N 类」，保证图上占比合计与圆心总额一致。
    private var chartSlices: [CategorySlice] {
        guard slices.count > 8 else { return slices }
        let rest = slices.dropFirst(8)
        let merged = CategorySlice(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008") ?? UUID(),
            name: "其他 \(rest.count) 类",
            emoji: "•••",
            colorHex: "9AA39E",
            amountMinor: rest.reduce(Int64(0)) { $0 + $1.amountMinor },
            count: rest.reduce(0) { $0 + $1.count }
        )
        return Array(slices.prefix(8)) + [merged]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    monthSwitcher
                    caliberPicker
                    caliberHint
                    summaryCard
                    insightSection
                    donutSection
                    rankSection
                    trendSection
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.pageBackground)
            .ledgerTabBarClearance()
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MonthlyReportView(month: monthAnchor)
                    } label: {
                        Label("月报", systemImage: "doc.text")
                    }
                }
            }
        }
    }

    private var monthSwitcher: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(Theme.subtleBackground, in: Circle())
            }
            Spacer()
            Text(monthTitle)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
                    .background(Theme.subtleBackground, in: Circle())
            }
            .disabled(isCurrentMonth)
            .opacity(isCurrentMonth ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.s)
    }

    private var isCurrentMonth: Bool {
        AppCalendar.gregorian.isDate(monthAnchor, equalTo: Date(), toGranularity: .month)
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
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(caliberDescription)
                if caliber == .personal && summary.pendingMinor > 0 {
                    Text("已剔除待报销 \(Money.format(summary.pendingMinor))")
                        .foregroundStyle(Theme.warning)
                } else if caliber == .personal && summary.expenseMinor > 0 && summary.expenseMinor == cashFlowExpense {
                    Text("本月没有待报销记录，所以这个口径与「现金流」结果相同。")
                        .foregroundStyle(.secondary)
                } else if caliber == .personal && summary.expenseMinor != cashFlowExpense {
                    Text("本月有已报销的垫付或报销差额，个人消费已按报销结果调整。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private var cashFlowExpense: Int64 {
        StatsEngine.summary(range: interval, caliber: .cashFlow, txns: liveTxns, claims: liveClaims).expenseMinor
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
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Text(caliber == .advance ? "本期垫付" : "本期支出")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(caliber.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            .foregroundStyle(.white.opacity(0.80))

            Text(Money.format(summary.expenseMinor))
                .font(Theme.Fonts.amountXL)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)

            HStack(spacing: Theme.Spacing.l) {
                heroStat(title: caliber == .advance ? "报销到账" : "收入", value: summary.incomeMinor)
                heroStat(title: "净额", value: summary.balanceMinor)
                if summary.pendingMinor > 0 {
                    heroStat(title: "待报销", value: summary.pendingMinor)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 150, height: 150)
                .offset(x: 54, y: -64)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func heroStat(title: String, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
            Text(Money.format(value))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(Theme.Fonts.amountM)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var insightSection: some View {
        Group {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    LedgerSectionHeader(title: "现金流洞察", detail: "固定按现金流口径")

                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: Theme.Spacing.s) {
                            Image(systemName: insight.symbol)
                                .font(.system(size: 14))
                                .foregroundStyle(insightColor(insight.level))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(insight.title)
                                    .font(.subheadline)
                                Text(insight.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            }
        }
    }

    private var insights: [Insight] {
        InsightEngine.generate(
            monthAnchor: monthAnchor,
            txns: liveTxns,
            categories: scopedCategories,
            claims: liveClaims
        )
    }

    private func insightColor(_ level: InsightLevel) -> Color {
        switch level {
        case .warning: return Theme.warning
        case .positive: return Theme.income
        case .info: return Theme.accent
        }
    }

    private var donutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            LedgerSectionHeader(title: caliber == .advance ? "垫付构成" : "支出构成")

            if slices.isEmpty {
                emptyHint
            } else {
                Chart(0..<chartSlices.count, id: \.self) { index in
                    let slice = chartSlices[index]
                    SectorMark(
                        angle: .value("金额", slice.amountMinor),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(categoryColor(for: slice))
                    .annotation(position: .overlay) {
                        let ratio = percentBase > 0 ? Double(slice.amountMinor) / Double(percentBase) : 0
                        if ratio >= 0.08 {
                            Text(String(format: "%.0f%%", ratio * 100))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(height: 170)
                .overlay {
                    VStack(spacing: 2) {
                        Text("合计").font(.caption2).foregroundStyle(.secondary)
                        Text(Money.format(totalExpense))
                            .font(Theme.Fonts.amountM)
                            .monospacedDigit()
                    }
                }

                legendGrid

                if breakdown.refundOffsetMinor < 0 {
                    Text("另有退款冲减 \(Money.format(-breakdown.refundOffsetMinor))，未分摊到具体分类；上方合计已扣除。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if breakdown.refundOffsetMinor > 0 {
                    Text("另有 \(Money.format(breakdown.refundOffsetMinor)) 支出未归入分类；上方合计已包含。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    /// 环形图图例：颜色 + 分类名 + 占比
    private var legendGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
            ForEach(Array(chartSlices.enumerated()), id: \.element.id) { index, slice in
                HStack(spacing: 5) {
                    Circle()
                        .fill(categoryColor(for: slice))
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

    private func categoryColor(for slice: CategorySlice) -> Color {
        guard let category = scopedCategories.first(where: { $0.id == slice.id }) else { return Theme.accent }
        return Color(hexString: category.colorHex)
    }

    private func percent(of slice: CategorySlice) -> Double {
        guard percentBase > 0 else { return 0 }
        return Double(slice.amountMinor) / Double(percentBase) * 100
    }

    private var rankSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            LedgerSectionHeader(title: "分类排行", detail: "点击查看明细")

            if slices.isEmpty {
                emptyHint
            } else {
                ForEach(Array(slices.prefix(10).enumerated()), id: \.element.id) { index, slice in
                    NavigationLink {
                        CategoryTxnListView(categoryId: slice.id, range: interval, title: slice.name, caliber: caliber)
                    } label: {
                        rankRow(slice, color: categoryColor(for: slice))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func rankRow(_ slice: CategorySlice, color: Color) -> some View {
        let ratio = percentBase > 0 ? Double(slice.amountMinor) / Double(percentBase) : 0
        return HStack(spacing: Theme.Spacing.m) {
            CategoryIconView(emoji: slice.emoji, name: slice.name, colorHex: slice.colorHex, size: 28)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .offset(x: 1, y: 1)
                }

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
                            .fill(color)
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
            LedgerSectionHeader(title: caliber == .advance ? "近 6 个月垫付" : "近 6 个月支出")

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("月份", monthLabel(bucket.monthStart)),
                    y: .value("支出", Double(bucket.expenseMinor) / 100.0)
                )
                .foregroundStyle(Theme.accent.gradient)
                .cornerRadius(6)
            }
            .frame(height: 160)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private var emptyHint: some View {
        Text(caliber == .advance ? "本月还没有垫付记录" : "本月还没有支出记录")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.l)
    }

    private var monthTitle: String {
        let comps = AppCalendar.gregorian.dateComponents([.year, .month], from: monthAnchor)
        return "\(comps.year ?? 0)年\(comps.month ?? 0)月"
    }

    /// 趋势图横轴标签去掉前导零（"01月" → "1月"）
    private func monthLabel(_ date: Date) -> String {
        let comps = AppCalendar.gregorian.dateComponents([.month], from: date)
        return "\(comps.month ?? 1)月"
    }

    private func shiftMonth(_ delta: Int) {
        if let next = AppCalendar.gregorian.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
        }
    }
}
