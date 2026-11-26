import Foundation

enum PeriodKind: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        case .custom: return "自定义"
        }
    }

    var summaryLabel: String {
        switch self {
        case .day: return "当日"
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "本年"
        case .custom: return "区间"
        }
    }
}

/// 首页的周期选择：日 / 周 / 月 / 年 / 自定义。
struct PeriodRange: Equatable {
    var kind: PeriodKind
    var anchor: Date
    var customStart: Date?
    var customEnd: Date?

    init(kind: PeriodKind = .month, anchor: Date = Date(), customStart: Date? = nil, customEnd: Date? = nil) {
        self.kind = kind
        self.anchor = anchor
        self.customStart = customStart
        self.customEnd = customEnd
    }

    func interval(calendar: Calendar = AppCalendar.gregorian) -> DateInterval {
        switch kind {
        case .day:
            let start = calendar.startOfDay(for: anchor)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
            return DateInterval(start: start, end: end)

        case .week:
            let start = Self.startOfWeek(anchor, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(604800)
            return DateInterval(start: start, end: end)

        case .month:
            return AppCalendar.monthInterval(containing: anchor)

        case .year:
            let comps = calendar.dateComponents([.year], from: anchor)
            let start = calendar.date(from: comps) ?? anchor
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? anchor
            return DateInterval(start: start, end: end)

        case .custom:
            let start = calendar.startOfDay(for: customStart ?? anchor)
            let rawEnd = calendar.startOfDay(for: customEnd ?? anchor)
            let end = calendar.date(byAdding: .day, value: 1, to: max(start, rawEnd)) ?? rawEnd
            return DateInterval(start: start, end: end)
        }
    }

    func title(calendar: Calendar = AppCalendar.gregorian) -> String {
        switch kind {
        case .day:
            return AppCalendar.dayTitle(anchor)
        case .week:
            let range = interval(calendar: calendar)
            let lastDay = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.start
            return "\(DateFormatter.ledgerShort.string(from: range.start)) – \(DateFormatter.ledgerShort.string(from: lastDay))"
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: anchor)
            return "\(comps.year ?? 0)年\(comps.month ?? 0)月"
        case .year:
            let comps = calendar.dateComponents([.year], from: anchor)
            return "\(comps.year ?? 0)年"
        case .custom:
            let range = interval(calendar: calendar)
            let lastDay = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.start
            return "\(DateFormatter.ledgerShort.string(from: range.start)) – \(DateFormatter.ledgerShort.string(from: lastDay))"
        }
    }

    /// 前后切换；自定义区间不参与切换
    func shifted(by delta: Int, calendar: Calendar = AppCalendar.gregorian) -> PeriodRange {
        guard kind != .custom else { return self }
        var next = self
        let unit: Calendar.Component
        switch kind {
        case .day: unit = .day
        case .week: unit = .weekOfYear
        case .month: unit = .month
        case .year: unit = .year
        case .custom: return self
        }
        next.anchor = calendar.date(byAdding: unit, value: delta, to: anchor) ?? anchor
        return next
    }

    /// 顶栏用的紧凑标题：11月 / 3月5日 / 3.1–3.10 / 2026年
    var compactTitle: String {
        let calendar = AppCalendar.gregorian
        switch kind {
        case .day:
            let comps = calendar.dateComponents([.month, .day], from: anchor)
            return "\(comps.month ?? 0)月\(comps.day ?? 0)日"
        case .week, .custom:
            let range = interval(calendar: calendar)
            let lastDay = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.start
            return "\(DateFormatter.ledgerShort.string(from: range.start))–\(DateFormatter.ledgerShort.string(from: lastDay))"
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: anchor)
            let isThisYear = (comps.year ?? 0) == calendar.component(.year, from: Date())
            let monthText = "\(comps.month ?? 0)月"
            return isThisYear ? monthText : "\(comps.year ?? 0)年\(monthText)"
        case .year:
            return "\(calendar.component(.year, from: anchor))年"
        }
    }

    /// 选中周/月/年时，列表是否按天分组
    var groupsByDay: Bool { true }

    static func startOfWeek(_ date: Date, calendar: Calendar = AppCalendar.gregorian) -> Date {
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = calendar.firstWeekday
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }
}
