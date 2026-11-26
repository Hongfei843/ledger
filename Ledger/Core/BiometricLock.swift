import Foundation
import LocalAuthentication

/// 面容 ID / 触控 ID / 设备密码锁。
/// 优先调用生物识别（Face ID / Touch ID）；不可用或被锁定才退到系统密码。
enum BiometricLock {
    static var capability: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    static var biometryName: String {
        switch capability {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        case .opticID: return "光学 ID"
        default: return "设备密码"
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static func authenticate(reason: String = "解锁轻账") async -> Bool {
        // 1) 优先面容/触控：真正走 Face ID，而不是直接弹密码
        let biometric = LAContext()
        biometric.localizedCancelTitle = "取消"
        biometric.localizedFallbackTitle = "输入设备密码"
        var error: NSError?
        if biometric.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                return try await biometric.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            } catch {
                // 用户取消/生物识别失败：继续尝试系统密码兜底
            }
        }

        // 2) 没有生物识别、被锁定或失败 → 系统密码
        let fallback = LAContext()
        fallback.localizedCancelTitle = "取消"
        do {
            return try await fallback.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
