import Foundation

/// 统一日历与日期区间计算，避免各处手写 Calendar 造成差异。
enum AppCalendar {
    static var gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone.current
        calendar.firstWeekday = 2 // 周一为一周起点
        return calendar
    }()

    static func startOfDay(_ date: Date) -> Date {
        gregorian.startOfDay(for: date)
    }

    static func startOfMonth(_ date: Date) -> Date {
        let comps = gregorian.dateComponents([.year, .month], from: date)
        return gregorian.date(from: comps) ?? startOfDay(date)
    }

    static func startOfNextMonth(_ date: Date) -> Date {
        gregorian.date(byAdding: .month, value: 1, to: startOfMonth(date)) ?? date
    }

    static func endOfMonth(_ date: Date) -> Date {
        startOfNextMonth(date).addingTimeInterval(-0.001)
    }

    /// "2026-11"
    static func monthKey(_ date: Date) -> String {
        let comps = gregorian.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }

    /// "11月23日 周日"
    static func dayTitle(_ date: Date) -> String {
        let comps = gregorian.dateComponents([.month, .day, .weekday], from: date)
        let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = comps.weekday ?? 1
        let name = weekdayNames[max(0, min(6, weekday - 1))]
        return "\(comps.month ?? 0)月\(comps.day ?? 0)日 \(name)"
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        gregorian.isDate(a, inSameDayAs: b)
    }

    /// 指定月份的第一天与最后一天
    static func monthInterval(containing date: Date) -> DateInterval {
        DateInterval(start: startOfMonth(date), end: startOfNextMonth(date))
    }

    static func days(in interval: DateInterval) -> [Date] {
        var result: [Date] = []
        var cursor = startOfDay(interval.start)
        let last = interval.end
        while cursor < last {
            result.append(cursor)
            guard let next = gregorian.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}
