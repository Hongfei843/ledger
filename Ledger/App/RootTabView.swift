import SwiftUI
import SwiftData
import Combine

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

    var body: some View {
        HStack(spacing: 2) {
            ForEach([LedgerTab.transactions, .stats, .claims, .assets, .settings], id: \.self) { tab in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                    .frame(height: 52)
                    .background(
                        selection == tab ? Theme.accent.opacity(0.11) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
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
        .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 10)
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

    @State private var showOnboarding = false
    @State private var showQuickEntry = false
    @State private var selectedTab: LedgerTab = .transactions

    /// 从系统「分享到本应用」或「用其他应用打开」传进来的文件
    @State private var sharedFile: SharedFile?

    /// 截图识别待确认的草稿（快捷指令 / 相册 / 文件导入）
    @State private var importDraft: ScreenshotImportDraft?
    @State private var importHint: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            TransactionListView()
                .tag(LedgerTab.transactions)

            StatsView()
                .tag(LedgerTab.stats)

            ClaimListView()
                .tag(LedgerTab.claims)

            AssetsHomeView()
                .tag(LedgerTab.assets)

            SettingsView()
                .tag(LedgerTab.settings)
        }
        .tint(Theme.accent)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LedgerFloatingTabBar(selection: $selectedTab)
        }
        // 切换主题色时强制重建，让所有引用 Theme.accent 的视图立即生效
        .id(accentHex)
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
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // 切到后台/任务切换器时用不透明遮罩盖住内容，避免被截图
            showPrivacyShield = phase != .active
            if phase == .background {
                unlocked = false
            }
            if phase == .active {
                takePendingScreenshotDraft()
            }
        }
        .onChange(of: showOnboarding) { _, showing in
            if !showing { takePendingScreenshotDraft() }
        }
        .onChange(of: unlocked) { _, didUnlock in
            if didUnlock { takePendingScreenshotDraft() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenshotImportReady)) { _ in
            takePendingScreenshotDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.quickActionNotification)) { note in
            if let type = note.object as? String {
                handleQuickAction(type)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .intentOpenEntry)) { _ in
            IntentBridge.clearPending()
            showQuickEntry = true
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
            try? context.save()
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
                case .entry: showQuickEntry = true
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

    // MARK: - 快速启动（长按桌面图标）

    private func handleQuickAction(_ type: String) {
        UserDefaults.standard.removeObject(forKey: AppDelegate.pendingQuickActionKey)
        switch type {
        case AppDelegate.entryAction:
            showQuickEntry = true
        case AppDelegate.screenshotAction:
            importScreenshotFromInbox()
        default:
            break
        }
    }

    // MARK: - 截图 / 文件入口

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
            sharedFile = SharedFile(url: url)
            return
        }

        sharedFile = SharedFile(url: url)
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
