import UIKit

/// 处理桌面快捷菜单（长按 App 图标）与「文件」App 打开文件两个入口。
///
/// 为什么要在 delegate 里再接一次文件打开：从「文件」App 点一个 `.ledgerbak` 时，
/// 系统可能走 legacy 的 `application(_:open:options:)` 而不是 SwiftUI 的 `.onOpenURL`，
/// 表现就是「App 被拉起来了，但界面里什么都没有」。这里把 URL 缓存下来，
/// 根视图启动后主动取一次，两条通道至少有一条能到。
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let quickActionNotification = Notification.Name("ledger.quickAction")
    static let openFileNotification = Notification.Name("ledger.openFile")
    static let pendingQuickActionKey = "quick.pendingAction"
    static let pendingFileURLKey = "files.pendingURL"

    static let entryAction = "com.ledger.quick.entry"
    static let screenshotAction = "com.ledger.quick.screenshot"

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        UserDefaults.standard.set(shortcutItem.type, forKey: Self.pendingQuickActionKey)
        NotificationCenter.default.post(name: Self.quickActionNotification, object: shortcutItem.type)
        completionHandler(true)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard url.isFileURL else { return false }
        UserDefaults.standard.set(url.absoluteString, forKey: Self.pendingFileURLKey)
        NotificationCenter.default.post(name: Self.openFileNotification, object: url)
        return true
    }

    /// 取出并清空待处理的文件 URL（只处理一次，避免重复弹窗）
    static func takePendingFileURL() -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: pendingFileURLKey),
              let url = URL(string: raw) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingFileURLKey)
        return url
    }
}
