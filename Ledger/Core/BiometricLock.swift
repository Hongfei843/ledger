import Foundation
import LocalAuthentication

/// 面容 ID / 设备密码锁。
/// 用 deviceOwnerAuthentication，没有面容的设备会自动退化为锁屏密码。
enum BiometricLock {
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static func authenticate(reason: String = "解锁轻账") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
