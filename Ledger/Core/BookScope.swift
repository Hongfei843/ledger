import Foundation

/// 当前账本。用一个 UserDefaults key 存当前 bookId，各页面按它做数据过滤。
enum BookScope {
    static let key = "book.currentId"

    static var currentId: UUID? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return UUID(uuidString: raw)
    }

    static func setCurrent(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// 页面里统一用这个判断：没设置当前账本时展示全部（保证首次启动不会空白）
    static func matches(_ bookId: UUID, raw: String) -> Bool {
        guard let current = UUID(uuidString: raw) else { return true }
        return current == bookId
    }
}
