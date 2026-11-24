import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            TransactionListView()
                .tabItem { Label("明细", systemImage: "list.bullet") }

            PlaceholderTab(title: "统计", note: "第 2 批实现")
                .tabItem { Label("统计", systemImage: "chart.pie") }

            PlaceholderTab(title: "报销", note: "第 2 批实现")
                .tabItem { Label("报销", systemImage: "doc.text") }

            PlaceholderTab(title: "负债", note: "第 3 批实现")
                .tabItem { Label("负债", systemImage: "creditcard") }

            SettingsView()
                .tabItem { Label("我的", systemImage: "person") }
        }
        .task {
            SeedData.bootstrapIfNeeded(context: context)
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
