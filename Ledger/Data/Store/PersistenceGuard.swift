import Foundation
import SwiftData

/// 统一的写入出口。
///
/// 目的只有一个：把散落各处的 `try? context.save()` 从「静默失败」改成「可感知失败」。
/// 记账 App 悄悄丢一笔账，比多弹一次提示严重得多——原来的写法遇到磁盘满、
/// 迁移冲突、约束失败时，内存里改过的对象还在，界面看起来像记成功了，重进 App 就没了。
///
/// 规则：
/// 1. 保存成功返回 `true`，调用方可以继续做后续动作；
/// 2. 保存失败立即 `rollback()`，把半截改动从内存里撤掉，避免残留脏对象被下一次保存带上；
/// 3. 失败原因写进 `Documents/写入失败日志.txt`，并广播通知，由根视图弹一条提示。
enum PersistenceGuard {
    @discardableResult
    static func save(_ context: ModelContext, _ action: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            PersistenceFailureCenter.shared.report(action: action, error: error)
            return false
        }
    }
}

/// 写入失败的广播中心：UI 监听通知弹提示，同时落盘一份日志方便事后排查。
final class PersistenceFailureCenter {
    static let shared = PersistenceFailureCenter()
    static let didFail = Notification.Name("ledger.persistence.didFail")
    /// 通知 `userInfo` 里的键
    static let actionKey = "action"
    static let reasonKey = "reason"
    static let messageKey = "message"

    private let lock = NSLock()
    private var lastMessage: String?
    private var totalCount = 0
    private let logURL: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        logURL = documents.appendingPathComponent("写入失败日志.txt")
    }

    func report(action: String, error: Error) {
        let reason = error.localizedDescription
        let text = "\(Self.stamp()) \(action)保存失败：\(reason)"

        lock.lock()
        totalCount += 1
        lastMessage = text
        lock.unlock()

        appendToLog(text)

        // 保存通常发生在主线程，但服务层也可能在别的队列调用；统一回主线程再发通知。
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didFail,
                object: nil,
                userInfo: [
                    Self.actionKey: action,
                    Self.reasonKey: reason,
                    Self.messageKey: text,
                ]
            )
        }
    }

    /// 自上次启动以来累计失败次数（诊断用）
    var failureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCount
    }

    var mostRecent: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastMessage
    }

    private func appendToLog(_ text: String) {
        guard let data = (text + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private static func stamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
