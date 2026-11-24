import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Theme.accentHexKey) private var accentHex: String = Theme.defaultAccentHex
    @AppStorage("onboarding.completed") private var onboardingCompleted = false

    @State private var showOnboarding = false

    /// 从系统「分享到本应用」或「用其他应用打开」传进来的文件
    @State private var sharedFile: SharedFile?

    var body: some View {
        TabView {
            TransactionListView()
                .tabItem { Label("明细", systemImage: "list.bullet") }

            StatsView()
                .tabItem { Label("统计", systemImage: "chart.pie") }

            ClaimListView()
                .tabItem { Label("报销", systemImage: "doc.text") }

            LoanListView()
                .tabItem { Label("负债", systemImage: "creditcard") }

            SettingsView()
                .tabItem { Label("我的", systemImage: "person") }
        }
        .tint(Color(hexString: accentHex))
        // 切换主题色时强制重建，让所有引用 Theme.accent 的视图立即生效
        .id(accentHex)
        .onOpenURL { url in
            sharedFile = SharedFile(url: url)
        }
        .sheet(item: $sharedFile) { file in
            NavigationStack {
                ImportView(initialFileURL: file.url)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .task {
            SeedData.bootstrapIfNeeded(context: context)
            if !onboardingCompleted {
                showOnboarding = true
            }
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

/// 分享进来的文件（Identifiable 以便用 sheet(item:) 呈现）
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}
