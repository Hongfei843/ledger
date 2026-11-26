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
    @State private var deletedBuffer: [Txn] = []
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
        let gross = periodTxns.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
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
            let gross = items.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
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
    /// 之前每个卡片各算一次，账户多时是 O(账户 × 流水)，列表滚动会卡。
    private var accountBalances: [UUID: Int64] {
        var map: [UUID: Int64] = [:]
        for account in accounts where account.deletedAt == nil && !account.isArchived && bookMatches(account.bookId) {
            map[account.id] = account.openingBalanceMinor
        }
        for txn in activeTxns {
            switch txn.type {
            case .expense:
                if let value = map[txn.accountId] { map[txn.accountId] = value - txn.amountMinor }
            case .income:
                if let value = map[txn.accountId] { map[txn.accountId] = value + txn.amountMinor }
            case .transfer:
                if let value = map[txn.accountId] { map[txn.accountId] = value - txn.amountMinor }
                if let counter = txn.counterAccountId, let value = map[counter] {
                    map[counter] = value + txn.amountMinor
                }
            case .adjustment:
                if let value = map[txn.accountId] { map[txn.accountId] = value + txn.amountMinor }
            case .loanPayment:
                break
            }
        }
        return map
    }

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
        let balances = accountBalances
        return NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    homeHeader(balances)

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
                                        Button {
                                            editingTxn = txn
                                        } label: {
                                            Text("编辑")
                                        }
                                        .tint(Theme.accent)
                                    }
                                }
                                .onDelete { offsets in
                                    delete(at: offsets, in: group)
                                }
                            } header: {
                                HStack {
                                    Text(AppCalendar.dayTitle(group.day))
                                    Spacer()
                                    if group.expenseMinor > 0 {
                                        Text("支出 \(Money.format(group.expenseMinor))")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(10)
                    .contentMargins(.top, 6, for: .scrollContent)
                }

                Button {
                    showEntry = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                        Text("记一笔")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .background(Theme.accent, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                }
                .padding(.trailing, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xxl)
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
            .navigationTitle("明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    periodMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $screenshotItem, matching: .images, photoLibrary: .shared()) {
                        if isScreenshotBusy {
                            ProgressView()
                        } else {
                            Image(systemName: "text.viewfinder")
                        }
                    }
                    .disabled(isScreenshotBusy)
                    .accessibilityLabel("截图识别记账")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SearchView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
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

    // MARK: - 周期切换

    private var periodMenu: some View {
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
            HStack(spacing: 4) {
                Text(period.compactTitle)
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
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

    private func homeHeader(_ balances: [UUID: Int64]) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            monthSummaryCard(balances)
                .padding(.horizontal, Theme.Spacing.l)
        }
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.s)
        .background(Theme.pageBackground)
    }

    private func monthSummaryCard(_ balances: [UUID: Int64]) -> some View {
        let netWorth = balances.values.reduce(Int64(0), +)
        return VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                summaryTile(title: "支出", emoji: "💸", amount: periodExpense, color: .primary)
                summaryTile(title: "收入", emoji: "💰", amount: periodIncome, color: Theme.income)
            }

            NavigationLink {
                AssetOverviewView()
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    metric("结余", Money.format(periodIncome - periodExpense))
                    Divider().frame(height: 18)
                    metric("昨日", Money.format(yesterdayExpense))
                    Divider().frame(height: 18)
                    metric("净资产", Money.format(netWorth))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 10)
                .cardStyle(radius: 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func summaryTile(title: String, emoji: String, amount: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 13))
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

    /// 资产为正、负债为负，直接相加即净资产
    private var netWorthMinor: Int64 {        accounts
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .reduce(Int64(0)) { partial, account in
                partial + BalanceService.balance(
                    of: account,
                    transactions: activeTxns,
                    openingBalanceMinor: account.openingBalanceMinor
                )
            }
    }

    /// 昨日支出
    private var yesterdayExpense: Int64 {
        let calendar = AppCalendar.gregorian
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return 0 }
        let start = calendar.startOfDay(for: yesterday)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let inDay = activeTxns.filter { $0.occurredAt >= start && $0.occurredAt < end }
        let gross = inDay.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
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
        let previousGross = previousTxns.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
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
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("\(greeting)，这里还空着")
                .font(.headline)
            Text("点右下角的 + 记第一笔")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
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
        toastAction = action
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toast = ToastState(message: message, actionTitle: actionTitle)
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            dismissToast()
        }
    }

    private func dismissToast() {
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

    private func delete(at offsets: IndexSet, in group: DayGroup) {
        var removed: [Txn] = []
        for index in offsets {
            let txn = group.items[index]
            txn.deletedAt = Date()
            txn.updatedAt = Date()
            removed.append(txn)
            // 删支出时连带软删除它的退款流水，撤销时一起恢复
            if txn.type == .expense {
                for refund in RefundService.refunds(of: txn, all: activeTxns) {
                    refund.deletedAt = Date()
                    refund.updatedAt = Date()
                    removed.append(refund)
                }
            }
        }
        try? context.save()
        refreshBalances()

        deletedBuffer = removed
        Haptics.warning()
        showToast("已删除 \(removed.count) 条", actionTitle: "撤销", duration: 5) {
            restoreDeleted()
        }
    }

    private func restoreDeleted() {
        for txn in deletedBuffer {
            txn.deletedAt = nil
            txn.updatedAt = Date()
        }
        deletedBuffer = []
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
            CategoryIconView(category: category, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(category?.name ?? txn.type.displayName)
                        .font(.subheadline)
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    /// 副标题：备注 · 账户（备注为空时只显示账户）
    private var subtitle: String {
        var parts: [String] = []
        if let note = txn.note, !note.isEmpty {
            parts.append(note)
        }
        if let payee = txn.payee, !payee.isEmpty {
            parts.append(payee)
        }
        if refundedMinor > 0 {
            parts.append("已退 \(Money.format(refundedMinor))")
        }
        parts.append(accountName)
        return parts.joined(separator: " · ")
    }
}
