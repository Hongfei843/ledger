import UIKit

/// 处理桌面快捷菜单（长按 App 图标）的入口。
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let quickActionNotification = Notification.Name("ledger.quickAction")
    static let pendingQuickActionKey = "quick.pendingAction"

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
}
