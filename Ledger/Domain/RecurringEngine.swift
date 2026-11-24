import Foundation

/// 周期性交易的日期推算（纯逻辑，便于测试）
enum RecurringEngine {
    static func nextDate(
        after date: Date,
        frequency: RecurrenceFrequency,
        interval: Int,
        calendar: Calendar = AppCalendar.gregorian
    ) -> Date? {
        let step = max(1, interval)
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: step, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: step, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: step, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: step, to: date)
        }
    }

    /// 算出从 rule.nextDate 到今天（含）之间所有应生成的日期。
    /// 最多返回 limit 条，避免长时间没用 App 后一次性灌入几百笔。
    static func dueDates(
        rule: RecurringRule,
        upTo today: Date,
        limit: Int = 40,
        calendar: Calendar = AppCalendar.gregorian
    ) -> [Date] {
        guard !rule.isPaused, rule.deletedAt == nil else { return [] }
        let end = calendar.startOfDay(for: today)
        var cursor = rule.nextDate
        var result: [Date] = []

        while calendar.startOfDay(for: cursor) <= end, result.count < limit {
            result.append(cursor)
            guard let next = nextDate(after: cursor, frequency: rule.frequency, interval: rule.interval, calendar: calendar) else {
                break
            }
            cursor = next
        }
        return result
    }
}
