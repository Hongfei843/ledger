import SwiftUI
import SwiftData
import PhotosUI

private struct DayGroup: Identifiable {
    let id: Date
    let day: Date
    let items: [Txn]
    let expenseMinor: Int64
}

struct TransactionListView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Txn> { $0.deletedAt == nil },
        sort: \Txn.occurredAt,
        order: .reverse
    ) private var allTxns: [Txn]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var loans: [Loan]
    @Query private var scheduleItems: [LoanScheduleItem]
    @Query private var statements: [Statement]
    @AppStorage(BookScope.key) private var currentBookRaw = ""

    @State private var showEntry = false
    @State private var editingTxn: Txn?
    @State private var period = PeriodRange()
    @State private var showCustomRange = false
    @State private var didRestorePeriod = false
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var toast: ToastState?
    @State private var toastAction: (() -> Void)?
    /// 连续删除时累积待撤销记录，撤销一次全部恢复，避免第一笔永久丢失。
    @State private var deletedBuffer: [Txn] = []
    @State private var toastTask: Task<Void, Never>?
    @State private var screenshotItem: PhotosPickerItem?
    @State private var isScreenshotBusy = false


    private struct ToastState: Equatable {
        let message: String
        let actionTitle: String?
    }

    private struct DueReminder: Identifiable {
        let id: String
        let title: String
        let detail: String
        let days: Int
        let accountId: UUID?
        let loanId: UUID?
    }

    private func bookMatches(_ id: UUID) -> Bool { BookScope.matches(id, raw: currentBookRaw) }

    private var activeTxns: [Txn] { allTxns.filter { bookMatches($0.bookId) } }
    private var interval: DateInterval { period.interval() }

    private var periodTxns: [Txn] {
        activeTxns.filter { interval.contains($0.occurredAt) }
    }

    private var periodRefund: Int64 {
        periodTxns.filter { RefundService.isRefund($0) }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var periodExpense: Int64 {
        let gross = periodTxns.filter { $0.type == .expense && $0.source != .reimbursement }.reduce(Int64(0)) { $0 + $1.amountMinor }
        return RefundService.netExpense(expenseMinor: gross, refundMinor: periodRefund)
    }

    private var periodIncome: Int64 {
        periodTxns
            .filter { $0.type == .income && !RefundService.isRefund($0) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var groups: [DayGroup] {
        var buckets: [Date: [Txn]] = [:]
        for txn in periodTxns {
            let key = AppCalendar.startOfDay(txn.occurredAt)
            buckets[key, default: []].append(txn)
        }
        return buckets.keys.sorted(by: >).map { key in
            let items = buckets[key] ?? []
            let gross = items.filter { $0.type == .expense && $0.source != .reimbursement }.reduce(Int64(0)) { $0 + $1.amountMinor }
            let refund = items.filter { RefundService.isRefund($0) }.reduce(Int64(0)) { $0 + $1.amountMinor }
            return DayGroup(id: key, day: key, items: items, expenseMinor: RefundService.netExpense(expenseMinor: gross, refundMinor: refund))
        }
    }

    /// 超过 30 天没对账、且确实有钱进出的账户
    private var staleAccounts: [Account] {
        let threshold = AppCalendar.gregorian.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let activeAccountIds = Set(
            activeTxns.flatMap { [$0.accountId, $0.counterAccountId].compactMap { $0 } }
        )
        return accounts.filter {
            $0.deletedAt == nil && !$0.isArchived && !$0.isSystem
                && bookMatches($0.bookId)
                && ($0.lastReconciledAt ?? .distantPast) < threshold
                && (activeAccountIds.contains($0.id) || $0.openingBalanceMinor != 0)
        }
    }

    /// 7 天内要还款的信用卡与贷款
    private var dueReminders: [DueReminder] {
        let calendar = AppCalendar.gregorian
        let today = calendar.startOfDay(for: Date())
        var result: [DueReminder] = []

        for account in accounts where account.deletedAt == nil && !account.isArchived && account.type.isCreditLike && bookMatches(account.bookId) {
            guard let billDay = account.billDay, let dueDay = account.dueDay, billDay > 0, dueDay > 0 else { continue }
            let cycle = CreditCardCycle(billDay: billDay, dueDay: dueDay)
            guard let due = cycle.dueDate(reference: Date()) else { continue }
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? 99
            guard days >= 0, days <= 7 else { continue }
            let info = CreditCardBillService.info(for: account, txns: activeTxns, statements: statements)
            let amount = info?.registered?.outstandingMinor ?? info?.estimatedAmountMinor ?? 0
            let dueText = "还款日 \(DateFormatter.ledgerShort.string(from: due))"
            result.append(
                DueReminder(
                    id: "card-\(account.id.uuidString)",
                    title: account.displayName,
                    detail: amount > 0 ? "\(dueText) · \(Money.format(amount))" : dueText,
                    days: days,
                    accountId: account.id,
                    loanId: nil
                )
            )
        }

        for item in scheduleItems where item.deletedAt == nil && !item.isPaid {
            guard let loan = loans.first(where: { $0.id == item.loanId && $0.deletedAt == nil && $0.status == .active }) else { continue }
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: item.dueDate)).day ?? 99
            guard days >= 0, days <= 7 else { continue }
            result.append(
                DueReminder(
                    id: "loan-\(item.id.uuidString)",
                    title: loan.name,
                    detail: "第 \(item.periodIndex) 期 · \(Money.format(item.totalMinor))",
                    days: days,
                    accountId: nil,
                    loanId: loan.id
                )
            )
        }

        return result.sorted { $0.days < $1.days }
    }

    /// 一次遍历算出所有账户余额。
    /// 每笔支出已退款合计（单次遍历，供列表与净支出展示）
    private var refundedByTxnId: [UUID: Int64] {
        var map: [UUID: Int64] = [:]
        for txn in activeTxns where RefundService.isRefund(txn) {
            if let originalId = txn.refundOfTxnId {
                map[originalId, default: 0] += txn.amountMinor
            }
        }
        return map
    }

    var body: some View {
        NavigationStack {
            // 完全自定义顶部栏，不再使用系统 Toolbar，避免 iOS 给 ToolbarItem 再加一层边框。
            VStack(spacing: 0) {
                topBar()

                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 0) {
                        homeHeader()
                        contentArea
                    }

                    entryButton
                }
            }
            .overlay(alignment: .top) {
                if let toast {
                    HStack(spacing: 8) {
                        Image(systemName: toast.actionTitle == nil ? "checkmark.circle.fill" : "trash.circle.fill")
                            .foregroundStyle(toast.actionTitle == nil ? Theme.income : Theme.warning)
                        Text(toast.message)
                            .font(.subheadline.weight(.medium))
                        if let title = toast.actionTitle {
                            Divider().frame(height: 16)
                            Button(title) {
                                toastAction?()
                                dismissToast()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: screenshotItem) { _, item in
                guard let item else { return }
                isScreenshotBusy = true
                Task {
                    defer {
                        isScreenshotBusy = false
                        screenshotItem = nil
                    }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let draft = await ScreenshotImportService.makeDraft(fromImageData: data) else {
                        return
                    }
                    ScreenshotImportStore.save(draft)
                }
            }
            .sheet(isPresented: $showEntry) {
                EntrySheet { message in
                    showToast(message, actionTitle: "再记一笔") {
                        showEntry = true
                    }
                }
                .presentationDetents([.large])
            }
            .sheet(item: $editingTxn) { txn in
                EntrySheet(editingTxn: txn) { message in
                    showToast(message)
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showCustomRange) {
                customRangeSheet
                    .presentationDetents([.height(300)])
            }
            .onAppear {
                if !didRestorePeriod {
                    didRestorePeriod = true
                    if let saved = PeriodPreference.load() {
                        period = saved
                    }
                }
                customStart = period.customStart ?? AppCalendar.startOfMonth(Date())
                customEnd = period.customEnd ?? Date()
            }
            .onChange(of: period) { _, newValue in
                PeriodPreference.save(range: newValue)
            }
        }
    }

    // MARK: - 内容区

    /// 有提醒或流水时走列表；整页为空时把空状态垂直居中在剩余空间里。
    /// 上一版把空状态塞在 List 顶部，卡片下面会留一大片空白、视觉重心全部压在屏幕上半部分。
    @ViewBuilder
    private var contentArea: some View {
        if groups.isEmpty && dueReminders.isEmpty && staleAccounts.isEmpty {
            VStack(spacing: 0) {
                Spacer(minLength: Theme.Spacing.xl)
                emptyState
                Spacer(minLength: Theme.Spacing.xxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, Theme.Layout.tabBarHeight)
        } else {
            transactionList
        }
    }

    private var transactionList: some View {
        List {
            if !dueReminders.isEmpty {
                Section {
                    ForEach(dueReminders) { item in
                        NavigationLink {
                            reminderDestination(item)
                        } label: {
                            reminderRow(item)
                        }
                    }
                } header: {
                    Text("即将到期")
                }
            }

            if !staleAccounts.isEmpty {
                Section {
                    NavigationLink {
                        ReconciliationView()
                    } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(Theme.warning)
                            Text("有 \(staleAccounts.count) 个账户超过 30 天未对账")
                                .font(.subheadline)
                            Spacer()
                            Text("去对账")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if groups.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items, id: \.id) { txn in
                            NavigationLink {
                                TxnDetailView(txn: txn)
                            } label: {
                                TxnRow(
                                    txn: txn,
                                    category: category(for: txn),
                                    accountName: accountName(for: txn),
                                    refundedMinor: refundedByTxnId[txn.id] ?? 0
                                )
                            }
                            .swipeActions(edge: .leading) {
                                if txn.canEditInEntrySheet {
                                    Button {
                                        editingTxn = txn
                                    } label: {
                                        Text("编辑")
                                    }
                                    .tint(Theme.accent)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if txn.canDeleteFromTransactionList {
                                    Button(role: .destructive) {
                                        delete(txn)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(AppCalendar.dayTitle(group.day))
                            Spacer()
                            if group.expenseMinor > 0 {
                                Text("支出 \(Money.format(group.expenseMinor))")
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.pageBackground)
        .listSectionSpacing(14)
        .contentMargins(.top, 0, for: .scrollContent)
        // 悬浮按钮浮在内容之上，列表底部要留出「按钮底边 + 按钮高度 + 呼吸」的总高度。
        .contentMargins(.bottom, Theme.Layout.fabClearance, for: .scrollContent)
    }

    private var entryButton: some View {
        Button {
            showEntry = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                Text("记一笔")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 56)
            .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.20), radius: 14, y: 6)
        }
        .buttonStyle(SoftPressButtonStyle())
        // 与 Tab 栏外缘对齐，避免悬浮按钮比底栏更靠里、看起来没对齐。
        .padding(.trailing, Theme.Spacing.m)
        // 真机截图已确认：页面铺满到屏幕底部，按钮需显式抬高一个 Tab 栏高度。
        .padding(.bottom, Theme.Layout.fabBottomOffset)
    }

    // MARK: - 自定义顶部栏

    private func topBar() -> some View {
        HStack(spacing: 0) {
            periodMenu
            Spacer(minLength: 8)
            trailingToolbar
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: 56)
        .background(Theme.pageBackground)
        .overlay {
            // 自定义区间时左侧胶囊会变宽，居中的「明细」会和它叠在一起，这种状态只保留区间标题。
            if period.kind != .custom {
                Text("明细")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
        }
    }

    private var trailingToolbar: some View {
        HStack(spacing: 0) {
            PhotosPicker(selection: $screenshotItem, matching: .images, photoLibrary: .shared()) {
                if isScreenshotBusy {
                    ProgressView()
                } else {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(width: 34, height: Theme.Layout.toolbarControlHeight)
            .contentShape(Rectangle())
            .disabled(isScreenshotBusy)
            .accessibilityLabel("截图识别记账")

            NavigationLink {
                SearchView()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: Theme.Layout.toolbarControlHeight)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("搜索")
        }
        .foregroundStyle(.secondary)
        .toolbarCapsuleStyle()
    }

    // MARK: - 周期切换

    private var periodMenu: some View {
        HStack(spacing: 0) {
            periodChevron(
                systemName: "chevron.left",
                label: "上一期",
                isEnabled: period.kind != .custom
            ) {
                period = period.shifted(by: -1)
            }

            periodPicker

            periodChevron(
                systemName: "chevron.right",
                label: "下一期",
                isEnabled: period.kind != .custom
            ) {
                period = period.shifted(by: 1)
            }
        }
        .toolbarCapsuleStyle()
    }

    /// 三个箭头统一字重与色阶，只按语义保留尺寸差异；禁用态也使用同一褪色比例。
    private func periodChevron(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.38))
                .frame(width: 28, height: Theme.Layout.toolbarControlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var periodPicker: some View {
        Menu {
            Button {
                period = period.shifted(by: -1)
            } label: {
                Label("上一期", systemImage: "chevron.left")
            }
            .disabled(period.kind == .custom)

            Button {
                period = period.shifted(by: 1)
            } label: {
                Label("下一期", systemImage: "chevron.right")
            }
            .disabled(period.kind == .custom)

            Divider()

            ForEach(PeriodKind.allCases) { kind in
                Button {
                if kind == .custom {
                    // 五页常驻，onAppear 不会在切页时重跑；这里用当前周期初始化才不会跳回启动时的月份。
                    customStart = period.customStart ?? AppCalendar.startOfMonth(period.anchor)
                    customEnd = period.customEnd ?? Date()
                    showCustomRange = true
                } else {
                        period = PeriodRange(kind: kind, anchor: period.anchor)
                    }
                } label: {
                    if period.kind == kind {
                        Label(kind.displayName, systemImage: "checkmark")
                    } else {
                        Text(kind.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(period.compactTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 12, alignment: .center)
            }
            .frame(height: Theme.Layout.toolbarControlHeight)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("当前周期 \(period.title())")
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("开始", selection: $customStart, displayedComponents: .date)
                DatePicker("结束", selection: $customEnd, in: customStart..., displayedComponents: .date)
            }
            .navigationTitle("自定义区间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showCustomRange = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        period = PeriodRange(
                            kind: .custom,
                            anchor: customStart,
                            customStart: customStart,
                            customEnd: customEnd
                        )
                        showCustomRange = false
                    }
                }
            }
        }
    }

    // MARK: - 汇总

    private func homeHeader() -> some View {
        VStack(spacing: Theme.Spacing.m) {
            monthSummaryCard()
                .padding(.horizontal, Theme.Spacing.l)
        }
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.s)
        // 与列表使用完全相同的纯色背景，不叠加渐变，避免出现横向色带。
        .background(Theme.pageBackground)
    }

    private func monthSummaryCard() -> some View {
        let netWorth = BalanceService.totals(accounts: accounts, transactions: allTxns, bookId: BookScope.currentId).netWorthMinor
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Label("本期支出", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let change = monthOverMonth {
                    Text("\(change >= 0 ? "较上期 +" : "较上期 ")\(String(format: "%.0f%%", change * 100))")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                }
            }
            .foregroundStyle(.white.opacity(0.82))

            Text(Money.format(periodExpense))
                .font(Theme.Fonts.amountXL)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .contentTransition(.numericText())

            HStack(spacing: Theme.Spacing.xl) {
                heroMetric(title: "收入", value: Money.format(periodIncome))
                heroMetric(title: "结余", value: Money.format(periodIncome - periodExpense))
                heroMetric(title: "昨日支出", value: Money.format(yesterdayExpense))
            }

            NavigationLink {
                AssetOverviewView()
            } label: {
                HStack {
                    Text("净资产")
                        .font(.caption)
                    Spacer()
                    Text(Money.format(netWorth))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.top, Theme.Spacing.m)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            // 顶部右侧的高光改成无硬边的径向渐变：原来的实心圆在渐变底色上会露出一道弧形接缝。
            RadialGradient(
                colors: [.white.opacity(0.10), .white.opacity(0.03), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 260
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
    }

    private func heroMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryTile(title: String, systemImage: String, amount: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(Money.format(amount))
                .font(Theme.Fonts.amountL)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .cardStyle(radius: 14)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.Fonts.amountS)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// 昨日支出
    private var yesterdayExpense: Int64 {
        let calendar = AppCalendar.gregorian
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return 0 }
        let start = calendar.startOfDay(for: yesterday)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let inDay = activeTxns.filter { $0.occurredAt >= start && $0.occurredAt < end }
        let gross = inDay.filter { $0.type == .expense && $0.source != .reimbursement }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let refund = inDay.filter { RefundService.isRefund($0) }.reduce(Int64(0)) { $0 + $1.amountMinor }
        return RefundService.netExpense(expenseMinor: gross, refundMinor: refund)
    }

    /// 仅按月视图时给出环比
    private var monthOverMonth: Double? {
        guard period.kind == .month else { return nil }
        let calendar = AppCalendar.gregorian
        let current = AppCalendar.monthInterval(containing: period.anchor)
        guard let previousStart = calendar.date(byAdding: .month, value: -1, to: current.start) else { return nil }
        let previous = DateInterval(start: previousStart, end: current.start)
        let previousTxns = activeTxns.filter { previous.contains($0.occurredAt) }
        let previousGross = previousTxns.filter { $0.type == .expense && $0.source != .reimbursement }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let previousRefund = previousTxns.filter { RefundService.isRefund($0) }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let previousExpense = RefundService.netExpense(expenseMinor: previousGross, refundMinor: previousRefund)
        guard previousExpense > 0 else { return nil }
        return (Double(periodExpense) - Double(previousExpense)) / Double(previousExpense)
    }

    private func summaryItem(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(Theme.Fonts.amountS)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func reminderRow(_ item: DueReminder) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "bell.badge")
                .font(.system(size: 14))
                .foregroundStyle(item.days <= 1 ? Theme.danger : Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline)
                Text(item.detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.days == 0 ? "今天" : "\(item.days) 天后")
                .font(.caption.weight(.medium))
                .foregroundStyle(item.days <= 1 ? Theme.danger : Theme.warning)
        }
    }

    @ViewBuilder
    private func reminderDestination(_ item: DueReminder) -> some View {
        if let accountId = item.accountId, let account = accounts.first(where: { $0.id == accountId }) {
            AccountDetailView(account: account)
        } else if let loanId = item.loanId, let loan = loans.first(where: { $0.id == loanId }) {
            LoanDetailView(loan: loan)
        } else {
            EmptyView()
        }
    }

    private var emptyState: some View {
        PremiumEmptyState(
            systemImage: "square.and.pencil",
            title: "\(greeting)，从第一笔开始",
            message: "每一笔都清楚，月底自然心里有数。\n点击右下角「记一笔」开始。"
        )
    }

    /// 按当前时段打招呼（借鉴 Cookie 的时间感知设计）
    private var greeting: String {
        let hour = AppCalendar.gregorian.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    private func showToast(_ message: String, actionTitle: String? = nil, duration: Double = 1.8, action: (() -> Void)? = nil) {
        // 新 toast 替换旧 toast 时取消旧计时器，否则第二条会比 5 秒更早消失。
        toastTask?.cancel()
        toastAction = action
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toast = ToastState(message: message, actionTitle: actionTitle)
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        withAnimation(.easeOut(duration: 0.22)) {
            toast = nil
        }
        toastAction = nil
    }

    private func category(for txn: Txn) -> Category? {
        categories.first { $0.id == txn.categoryId }
    }

    private func accountName(for txn: Txn) -> String {
        accounts.first { $0.id == txn.accountId }?.displayName ?? "—"
    }

    private func delete(_ txn: Txn) {
        var removed: [Txn] = [txn]
        txn.deletedAt = Date()
        txn.updatedAt = Date()
        // 删支出时连带软删除它的退款流水，撤销时一起恢复。
        if txn.type == .expense {
            for refund in RefundService.refunds(of: txn, all: activeTxns) {
                refund.deletedAt = Date()
                refund.updatedAt = Date()
                removed.append(refund)
            }
        }
        if txn.type == .transfer, let creditAccountId = txn.counterAccountId {
            StatementSettlementService.rebuild(
                accountId: creditAccountId,
                transactions: allTxns,
                statements: statements
            )
        }
        try? context.save()
        refreshBalances()

        deletedBuffer.append(contentsOf: removed)
        Haptics.warning()
        showToast("已删除 \(removed.count) 条", actionTitle: "撤销", duration: 5) {
            restoreDeleted()
        }
    }

    private func restoreDeleted() {
        let restored = deletedBuffer
        let creditAccountIds = Set(restored.compactMap { $0.type == .transfer ? $0.counterAccountId : nil })
        for txn in restored {
            txn.deletedAt = nil
            txn.updatedAt = Date()
        }
        deletedBuffer = []
        let restoredIds = Set(restored.map { $0.id })
        let transactions = allTxns.filter { !restoredIds.contains($0.id) } + restored
        for accountId in creditAccountIds {
            StatementSettlementService.rebuild(accountId: accountId, transactions: transactions, statements: statements)
        }
        try? context.save()
        refreshBalances()
        Haptics.success()
    }

    private func refreshBalances() {
        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        try? context.save()
    }
}

struct TxnRow: View {
    let txn: Txn
    let category: Category?
    let accountName: String
    var refundedMinor: Int64 = 0

    private var amountColor: Color {
        switch txn.type {
        case .income: return Theme.income
        case .transfer: return Theme.transfer
        case .adjustment: return Theme.transfer
        default: return .primary
        }
    }

    private var amountPrefix: String {
        switch txn.type {
        case .income: return "+"
        case .transfer: return ""
        case .adjustment: return txn.amountMinor >= 0 ? "+" : "-"
        default: return "-"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            CategoryIconView(category: category, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(primaryTitle)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if txn.isRefund {
                        Text("退款")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.income.opacity(0.14), in: Capsule())
                            .foregroundStyle(Theme.income)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .lineLimit(1)
            }

            Spacer()

            Text(amountPrefix + Money.format(abs(txn.amountMinor)))
                .font(Theme.Fonts.amountM)
                .monospacedDigit()
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 2)
    }

    private var primaryTitle: String {
        if let payee = txn.payee, !payee.isEmpty { return payee }
        return category?.name ?? txn.type.displayName
    }

    /// 商家作为主标题，分类、备注与账户退居第二层，扫读更接近真实账单。
    private var subtitle: String {
        var parts: [String] = []
        if txn.payee?.isEmpty == false, let categoryName = category?.name {
            parts.append(categoryName)
        }
        if let note = txn.note, !note.isEmpty {
            parts.append(note)
        }
        if refundedMinor > 0 {
            parts.append("已退 \(Money.format(refundedMinor))")
        }
        parts.append(accountName)
        return parts.joined(separator: " · ")
    }
}
