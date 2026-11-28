import SwiftUI
import SwiftData
import Combine
import UIKit

enum LedgerTab: Int, Hashable {
    case transactions, stats, claims, assets, settings

    var title: String {
        switch self {
        case .transactions: "明细"
        case .stats: "统计"
        case .claims: "报销"
        case .assets: "资产"
        case .settings: "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .transactions: "list.bullet.rectangle"
        case .stats: "chart.pie"
        case .claims: "doc.text"
        case .assets: "building.columns"
        case .settings: "person"
        }
    }
}

struct LedgerFloatingTabBar: View {
    @Binding var selection: LedgerTab
    /// 选中胶囊用同一份几何在五个位置之间滑动，而不是每个位置各画一个。
    @Namespace private var pill

    private let tabs: [LedgerTab] = [.transactions, .stats, .claims, .assets, .settings]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    guard selection != tab else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: selection == tab ? .semibold : .regular))
                            .frame(height: 20)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab ? Theme.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Layout.tabBarHeight - 16)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(Theme.accent.opacity(0.11))
                                .matchedGeometryEffect(id: "tabPill", in: pill)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, 4)
    }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Theme.accentHexKey) private var accentHex: String = Theme.defaultAccentHex
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @AppStorage("security.lockEnabled") private var lockEnabled = false

    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false
    @State private var showPrivacyShield = false
    /// 上一次的 scenePhase：用来判断这次 .inactive 是「要走后台」还是「刚从后台回来」。
    @State private var previousPhase: ScenePhase = .background
    /// 进程启动后是否已经真正到过前台。冷启动那次 .inactive 不需要遮罩。
    @State private var hasActivatedOnce = false

    @State private var showOnboarding = false
    @State private var showQuickEntry = false
    /// 锁屏期间来自 Siri / 桌面快捷方式的动作，解锁后再执行，避免余额与表单暴露在锁屏之上。
    @State private var pendingQuickEntry = false
    @State private var pendingSharedFile: SharedFile?
    @State private var selectedTab: LedgerTab = .transactions

    /// 从系统「分享到本应用」或「用其他应用打开」传进来的文件
    @State private var sharedFile: SharedFile?

    /// 截图识别待确认的草稿（快捷指令 / 相册 / 文件导入）
    @State private var importDraft: ScreenshotImportDraft?
    @State private var importHint: String?

    /// 写入失败提示：保存失败时短暂浮在顶部，避免「记了但没存上」变成静默事故
    @State private var writeFailureText: String?

    var body: some View {
        // 不再使用系统 TabView，避免 iOS 26 即使隐藏 tabItem 仍残留空白胶囊背景。
        // 五页常驻可保留各自的导航与滚动状态，非当前页不接收触摸和辅助功能焦点。
        ZStack {
            tabLayer(.transactions) { TransactionListView() }
            tabLayer(.stats) { StatsView() }
            tabLayer(.claims) { ClaimListView() }
            tabLayer(.assets) { AssetsHomeView() }
            tabLayer(.settings) { SettingsView() }
        }
        .tint(Theme.accent)
        // 自定义 Tab 栏占据底部安全区；子页面悬浮按钮据此避让，不再依赖系统 TabView。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LedgerFloatingTabBar(selection: $selectedTab)
        }
        // 主题色变化只触发重绘，不重建根视图；否则导航栈、周期选择与滚动位置会全部复位。
        .onChange(of: accentHex) { _, _ in Haptics.selection() }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .sheet(item: $sharedFile) { file in
            NavigationStack {
                ImportView(initialFileURL: file.url)
            }
        }
        .sheet(item: $importDraft) { draft in
            EntrySheet(prefill: EntrySheetPrefill(draft: draft))
                .presentationDetents([.large])
        }
        .alert(
            "截图导入",
            isPresented: Binding(
                get: { importHint != nil },
                set: { if !$0 { importHint = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importHint ?? "")
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $showQuickEntry) {
            EntrySheet()
                .presentationDetents([.large])
        }
        .overlay {
            if lockEnabled && !unlocked {
                LockScreenView { unlocked = true }
                    .transition(.identity)
            }
        }
        .animation(nil, value: unlocked)
        .overlay {
            if showPrivacyShield {
                PrivacyShieldView()
            }
        }
        .overlay(alignment: .top) {
            if let writeFailureText {
                Text(writeFailureText)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.danger.opacity(0.28), lineWidth: 0.8)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.88), value: writeFailureText)
        .onReceive(NotificationCenter.default.publisher(for: PersistenceFailureCenter.didFail)) { note in
            let action = note.userInfo?[PersistenceFailureCenter.actionKey] as? String ?? "改动"
            let reason = note.userInfo?[PersistenceFailureCenter.reasonKey] as? String ?? ""
            Haptics.warning()
            withAnimation { writeFailureText = "「\(action)」没保存成功，已撤销这次改动\n\(reason)" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // 只清掉自己这一条，别把后面又冒出来的失败提示一起抹掉
                if writeFailureText?.hasPrefix("「\(action)」") == true {
                    withAnimation { writeFailureText = nil }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: showOnboarding) { _, showing in
            if !showing { takePendingScreenshotDraft() }
        }
        .onChange(of: unlocked) { _, didUnlock in
            guard didUnlock else { return }
            takePendingScreenshotDraft()
            if pendingQuickEntry {
                pendingQuickEntry = false
                showQuickEntry = true
            }
            if let file = pendingSharedFile {
                pendingSharedFile = nil
                sharedFile = file
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenshotImportReady)) { _ in
            takePendingScreenshotDraft()
        }
        // 系统在窗口真正显示之前就发这个通知：此刻撤掉遮罩，用户看不到「内容已隐藏」的那一帧；
        // 后台期间遮罩一直盖着，任务切换器的快照仍然受保护。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            showPrivacyShield = false
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.quickActionNotification)) { note in
            if let type = note.object as? String {
                handleQuickAction(type)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .intentOpenEntry)) { _ in
            IntentBridge.clearPending()
            presentEntry()
        }
        .onReceive(NotificationCenter.default.publisher(for: .intentImportScreenshot)) { _ in
            IntentBridge.clearPending()
            importScreenshotFromInbox()
        }
        .task {
            SeedData.bootstrapIfNeeded(context: context)
            ReimbursementSettlementService.backfillMissingShortfalls(context: context)
            let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
            let statements = (try? context.fetch(FetchDescriptor<Statement>())) ?? []
            let allTxns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
            for account in accounts where account.type.isCreditLike && account.deletedAt == nil {
                StatementSettlementService.rebuild(
                    accountId: account.id,
                    transactions: allTxns,
                    statements: statements
                )
            }
            PersistenceGuard.save(context, "启动自检重建账单")
            let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
            let liveBooks = books.filter { $0.deletedAt == nil }
            if let current = BookScope.currentId, liveBooks.contains(where: { $0.id == current }) {
                // 当前账本有效
            } else if let book = liveBooks.first(where: { $0.isDefault }) ?? liveBooks.first {
                BookScope.setCurrent(book.id)
            }
            if let pending = UserDefaults.standard.string(forKey: AppDelegate.pendingQuickActionKey) {
                handleQuickAction(pending)
            }
            if let action = IntentBridge.takePending() {
                switch action {
                case .entry: presentEntry()
                case .screenshot: importScreenshotFromInbox()
                }
            }
            // 补记周期交易（房租、订阅等），失败不影响启动
            _ = RecurringService.run(context: context)
            if !onboardingCompleted {
                showOnboarding = true
            }
            // 快捷指令拉起 App 时，识别结果可能比 UI 晚一点点
            try? await Task.sleep(nanoseconds: 600_000_000)
            takePendingScreenshotDraft()
        }
    }

    // MARK: - 前后台与隐私遮罩

    /// 隐私遮罩只在「确实要离开前台」时出现：
    /// 1) 冷启动时系统会先给一次 .inactive，这时屏幕上还没有账目，不再弹遮罩（消除开机闪一下「内容已隐藏」）；
    /// 2) 从后台回来时，系统同样先给一次 .inactive，但此时隐私快照已经拍完，直接撤掉遮罩，不再多留半秒。
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            hasActivatedOnce = true
            showPrivacyShield = false
            takePendingScreenshotDraft()
        case .inactive:
            if previousPhase == .background {
                showPrivacyShield = false
            } else if hasActivatedOnce {
                // 正在被系统盖住（任务切换器 / 通知中心 / 锁屏），先遮住再让系统截图
                showPrivacyShield = true
            }
        case .background:
            showPrivacyShield = true
            unlocked = false
        @unknown default:
            break
        }
        previousPhase = phase
    }

    // MARK: - 快速启动（长按桌面图标）

    /// 记账面板统一入口：应用锁未解除时暂存动作，解锁后再弹出。
    private func presentEntry() {
        if lockEnabled && !unlocked {
            pendingQuickEntry = true
            return
        }
        pendingQuickEntry = false
        showQuickEntry = true
    }

    /// 分享进来的文件同样受应用锁保护。
    private func presentSharedFile(_ file: SharedFile) {
        if lockEnabled && !unlocked {
            pendingSharedFile = file
            return
        }
        sharedFile = file
    }

    private func handleQuickAction(_ type: String) {
        UserDefaults.standard.removeObject(forKey: AppDelegate.pendingQuickActionKey)
        switch type {
        case AppDelegate.entryAction:
            presentEntry()
        case AppDelegate.screenshotAction:
            importScreenshotFromInbox()
        default:
            break
        }
    }

    // MARK: - 截图 / 文件入口

    private func tabLayer<Content: View>(_ tab: LedgerTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            // 翻页用 0.16s 的短交叉淡入，比跟随胶囊的弹簧更利落，也不会拖出残影。
            .animation(.easeOut(duration: 0.16), value: selectedTab)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
            .zIndex(selectedTab == tab ? 1 : 0)
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme == "ledger" {
            if url.host == "import-screenshot" {
                importScreenshotFromInbox()
            }
            return
        }

        if url.isFileURL {
            if ScreenshotInbox.isImageFile(url) {
                importScreenshot(fromFileURL: url)
                return
            }
            presentSharedFile(SharedFile(url: url))
            return
        }

        // 非 file URL 不该被当成 CSV 文件读取（Info.plist 收敛后也不应再出现），直接忽略。
    }

    /// 快捷指令把截图存进「轻账」目录后，用 ledger://import-screenshot 触发
    private func importScreenshotFromInbox() {
        Task {
            guard let found = ScreenshotInbox.latestImage() else {
                importHint = "没找到刚保存的截图。\n在快捷指令里把截图「存储文件」到「我的 iPhone → 轻账」，再打开本应用。"
                return
            }
            let draft = await ScreenshotImportService.makeDraft(from: found.image)
            ScreenshotInbox.consume(found.url)
            present(draft)
        }
    }

    private func importScreenshot(fromFileURL url: URL) {
        Task {
            guard let draft = await ScreenshotImportService.makeDraft(fromFileURL: url) else {
                importHint = "这张文件读不出来，换一张图片试试。"
                return
            }
            present(draft)
        }
    }

    private func present(_ draft: ScreenshotImportDraft) {
        // 应用锁未解锁时不弹表单，先存起来，解锁后再弹，避免金额露在锁屏上
        if lockEnabled && !unlocked {
            ScreenshotImportStore.save(draft)
            return
        }
        ScreenshotImportStore.clear()
        importDraft = draft
    }

    private func takePendingScreenshotDraft() {
        guard importDraft == nil, !showOnboarding, !(lockEnabled && !unlocked) else { return }
        if let draft = ScreenshotImportStore.take() {
            importDraft = draft
        }
    }
}

/// 隐私遮罩：切后台时盖住内容，防止任务切换器里看到账目
struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Theme.pageBackground
                .ignoresSafeArea()
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("轻账")
                    .font(.headline)
                Text("内容已隐藏")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 分享进来的文件（Identifiable 以便用 sheet(item:) 呈现）
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// 应用锁
struct LockScreenView: View {
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                Text("轻账已锁定")
                    .font(.headline)
                Text("用面容 ID 或设备密码解锁")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("解锁") {
                    unlock()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .task {
            if await BiometricLock.authenticate() {
                onUnlock()
            }
        }
    }

    private func unlock() {
        Task {
            if await BiometricLock.authenticate() {
                onUnlock()
            }
        }
    }
}
