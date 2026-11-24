import XCTest
import Foundation
@testable import Ledger

final class PeriodRangeTests: XCTestCase {
    private let calendar = AppCalendar.gregorian

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return calendar.date(from: comps)!
    }

    func testDayInterval() {
        let range = PeriodRange(kind: .day, anchor: date(2026, 11, 24))
        let interval = range.interval(calendar: calendar)
        let comps = calendar.dateComponents([.hour, .minute], from: interval.end)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(calendar.dateComponents([.day], from: interval.start, to: interval.end).day, 1)
    }

    /// 周一为一周起点（firstWeekday = 2）
    func testWeekStartsMonday() {
        let range = PeriodRange(kind: .week, anchor: date(2026, 11, 24)) // 周二
        let interval = range.interval(calendar: calendar)
        let weekday = calendar.component(.weekday, from: interval.start)
        XCTAssertEqual(weekday, 2, "一周应从周一开始")
        XCTAssertEqual(calendar.dateComponents([.day], from: interval.start, to: interval.end).day, 7)
    }

    func testMonthInterval() {
        let range = PeriodRange(kind: .month, anchor: date(2026, 11, 24))
        let interval = range.interval(calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: interval.start), 11)
        XCTAssertEqual(calendar.component(.day, from: interval.start), 1)
    }

    func testYearInterval() {
        let range = PeriodRange(kind: .year, anchor: date(2026, 11, 24))
        let interval = range.interval(calendar: calendar)
        XCTAssertEqual(calendar.component(.year, from: interval.start), 2026)
        XCTAssertEqual(calendar.component(.month, from: interval.start), 1)
        XCTAssertEqual(calendar.component(.day, from: interval.start), 1)
    }

    /// 自定义区间应包含结束日当天
    func testCustomRangeIncludesEndDay() {
        let range = PeriodRange(
            kind: .custom,
            anchor: date(2026, 11, 24),
            customStart: date(2026, 10, 1),
            customEnd: date(2026, 10, 5)
        )
        let interval = range.interval(calendar: calendar)
        let inside = date(2026, 10, 5)
        XCTAssertTrue(interval.contains(inside), "结束日当天应包含在内")
        XCTAssertFalse(interval.contains(date(2026, 10, 6)))
    }

    func testShiftMonth() {
        let range = PeriodRange(kind: .month, anchor: date(2026, 11, 24))
        let previous = range.shifted(by: -1, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: previous.anchor), 10)
    }

    func testShiftCustomDoesNothing() {
        let range = PeriodRange(kind: .custom, anchor: date(2026, 11, 24), customStart: date(2026, 10, 1), customEnd: date(2026, 10, 5))
        XCTAssertEqual(range.shifted(by: -1).anchor, range.anchor)
    }

    func testTitleNotEmpty() {
        for kind in PeriodKind.allCases {
            let range = PeriodRange(kind: kind, anchor: date(2026, 11, 24), customStart: date(2026, 11, 1), customEnd: date(2026, 11, 10))
            XCTAssertFalse(range.title(calendar: calendar).isEmpty)
        }
    }
}
