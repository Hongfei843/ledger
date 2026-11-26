import SwiftUI
import SwiftData
import Combine

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

    /// 从系统「分享到本应用」或「用其他应用打开」传进来的文件
    @State private var sharedFile: SharedFile?

    /// 截图识别待确认的草稿（快捷指令 / 相册 / 文件导入）
    @State private var importDraft: ScreenshotImportDraft?
    @State private var importHint: String?

    var body: some View {
        TabView {
            TransactionListView()
                .tabItem { Label("明细", systemImage: "list.bullet") }

            StatsView()
                .tabItem { Label("统计", systemImage: "chart.pie") }

            ClaimListView()
                .tabItem { Label("报销", systemImage: "doc.text") }

            AssetsHomeView()
                .tabItem { Label("资产", systemImage: "building.columns") }

            SettingsView()
                .tabItem { Label("我的", systemImage: "person") }
        }
        .tint(Color(hexString: accentHex))
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
        .task {
            SeedData.bootstrapIfNeeded(context: context)
            if let pending = UserDefaults.standard.string(forKey: AppDelegate.pendingQuickActionKey) {
                handleQuickAction(pending)
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

struct PlaceholderTab: View {
    let title: String
    let note: String

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageBackground)
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
