import Foundation

extension Notification.Name {
    /// 快捷指令 / 相册识别出截图后发出，App 收到后弹出预填的「记一笔」
    static let screenshotImportReady = Notification.Name("ledger.screenshotImportReady")
}

/// 截图识别出来的草稿：先落盘到 UserDefaults，再打开 App 由用户确认。
struct ScreenshotImportDraft: Codable, Equatable, Identifiable {
    var id: UUID
    var amountMinor: Int64?
    var payee: String?
    var confidence: Double
    var rawText: String
    var createdAt: Date

    var hasAmount: Bool { (amountMinor ?? 0) > 0 }

    init(
        id: UUID = UUID(),
        amountMinor: Int64?,
        payee: String?,
        confidence: Double,
        rawText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amountMinor = amountMinor
        self.payee = payee
        self.confidence = confidence
        // OCR 原文只留一小段，够排查即可，不塞满 UserDefaults
        self.rawText = String(rawText.prefix(600))
        self.createdAt = createdAt
    }
}

/// 草稿的存取。快捷指令把图交给 App 后可能还没冷启动完成，
/// 所以先写 UserDefaults，App 起来后再取；超过 10 分钟视为过期。
enum ScreenshotImportStore {
    static let storageKey = "screenshot.pendingDraft"
    static let maxAge: TimeInterval = 10 * 60

    static func save(_ draft: ScreenshotImportDraft, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: .screenshotImportReady, object: nil)
    }

    static func pending(defaults: UserDefaults = .standard, now: Date = Date()) -> ScreenshotImportDraft? {
        guard let data = defaults.data(forKey: storageKey),
              let draft = try? JSONDecoder().decode(ScreenshotImportDraft.self, from: data) else {
            return nil
        }
        guard now.timeIntervalSince(draft.createdAt) <= maxAge else {
            defaults.removeObject(forKey: storageKey)
            return nil
        }
        return draft
    }

    /// 取一次就清掉，避免重复弹窗
    @discardableResult
    static func take(defaults: UserDefaults = .standard, now: Date = Date()) -> ScreenshotImportDraft? {
        guard let draft = pending(defaults: defaults, now: now) else { return nil }
        defaults.removeObject(forKey: storageKey)
        return draft
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
