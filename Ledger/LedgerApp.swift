import SwiftUI

@main
struct LedgerApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

/// 临时骨架：仅用于验证云端构建链路。
/// 第 1 批会把这里替换为真正的 5 Tab 结构。
struct RootTabView: View {
    var body: some View {
        TabView {
            Text("明细")
                .tabItem { Label("明细", systemImage: "list.bullet") }
            Text("统计")
                .tabItem { Label("统计", systemImage: "chart.pie") }
            Text("报销")
                .tabItem { Label("报销", systemImage: "doc.text") }
            Text("负债")
                .tabItem { Label("负债", systemImage: "creditcard") }
            Text("我的")
                .tabItem { Label("我的", systemImage: "person") }
        }
    }
}
