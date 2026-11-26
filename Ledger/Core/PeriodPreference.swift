import Foundation

/// 首页周期选择的持久化（记住上次看的是日/周/月/年/自定义）。
struct PeriodPreference: Codable, Equatable {
    var kindRaw: String
    var anchor: Date
    var customStart: Date?
    var customEnd: Date?

    static let storageKey = "home.periodPreference"

    init(range: PeriodRange) {
        self.kindRaw = range.kind.rawValue
        self.anchor = range.anchor
        self.customStart = range.customStart
        self.customEnd = range.customEnd
    }

    var range: PeriodRange? {
        guard let kind = PeriodKind(rawValue: kindRaw) else { return nil }
        return PeriodRange(kind: kind, anchor: anchor, customStart: customStart, customEnd: customEnd)
    }

    static func save(range: PeriodRange, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(PeriodPreference(range: range)) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load(defaults: UserDefaults = .standard) -> PeriodRange? {
        guard let data = defaults.data(forKey: storageKey),
              let preference = try? JSONDecoder().decode(PeriodPreference.self, from: data) else {
            return nil
        }
        return preference.range
    }
}
