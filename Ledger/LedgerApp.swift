import SwiftUI
import SwiftData
import UIKit

@main
struct LedgerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer? = ModelContainerFactory.make()

    var body: some Scene {
        WindowGroup {
            if let container {
                RootTabView()
                    .modelContainer(container)
            } else {
                BootErrorView()
            }
        }
    }
}

/// 数据初始化失败时的可读错误页，不允许白屏。
struct BootErrorView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Theme.warning)
            Text("数据初始化失败")
                .font(.headline)
            Text("请尝试从备份恢复，或重新安装应用。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.xl)
    }
}
