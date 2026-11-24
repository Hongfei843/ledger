import XCTest
import Foundation
@testable import Ledger

final class CreditCardCycleTests: XCTestCase {
    private let calendar = AppCalendar.gregorian

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return calendar.date(from: comps)!
    }

    /// 账单日 5、还款日 25：11/24 时，最近出账日是 11/5，还款日是 11/25
    func testSameMonthDue() {
        let cycle = CreditCardCycle(billDay: 5, dueDay: 25)
        let ref = date(2026, 11, 24)

        let bill = cycle.latestBillDate(reference: ref)
        XCTAssertEqual(calendar.component(.day, from: bill ?? ref), 5)
        XCTAssertEqual(calendar.component(.month, from: bill ?? ref), 11)

        let due = cycle.dueDate(reference: ref)
        XCTAssertEqual(calendar.component(.day, from: due ?? ref), 25)
        XCTAssertEqual(calendar.component(.month, from: due ?? ref), 11)
        XCTAssertEqual(cycle.daysUntilDue(reference: ref), 1)
    }

    /// 还款日早于账单日时，还款日落在次月
    func testDueNextMonthWhenDueDayBeforeBillDay() {
        let cycle = CreditCardCycle(billDay: 20, dueDay: 8)
        let ref = date(2026, 11, 24)

        let due = cycle.dueDate(reference: ref)
        XCTAssertEqual(calendar.component(.day, from: due ?? ref), 8)
        XCTAssertEqual(calendar.component(.month, from: due ?? ref), 12)
    }

    /// 账单周期应为「上月出账次日 ~ 本月出账日」
    func testStatementPeriod() {
        let cycle = CreditCardCycle(billDay: 5, dueDay: 25)
        let ref = date(2026, 11, 24)

        guard let period = cycle.statementPeriod(reference: ref) else {
            return XCTFail("应能算出账期")
        }
        let startComps = calendar.dateComponents([.month, .day], from: period.start)
        XCTAssertEqual(startComps.month, 10)
        XCTAssertEqual(startComps.day, 6)

        let lastDay = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.end
        let endComps = calendar.dateComponents([.month, .day], from: lastDay)
        XCTAssertEqual(endComps.month, 11)
        XCTAssertEqual(endComps.day, 5)
    }

    /// 账单日 31 在 2 月应被收敛到当月最后一天
    func testBillDayClampedToMonthLength() {
        let cycle = CreditCardCycle(billDay: 31, dueDay: 20)
        let ref = date(2026, 3, 5) // 3/5 时最近出账日是 2 月
        guard let bill = cycle.latestBillDate(reference: ref) else {
            return XCTFail("应能算出出账日")
        }
        let comps = calendar.dateComponents([.month, .day], from: bill)
        XCTAssertEqual(comps.month, 2)
        XCTAssertEqual(comps.day, 28)
    }

    func testDaysUntilDueIsNegativeAfterDue() {
        let cycle = CreditCardCycle(billDay: 5, dueDay: 25)
        let ref = date(2026, 11, 28) // 已过 11/25，最近账单变为本期
        // 11/28 时最近出账日仍是 11/5，还款日 11/25 已过
        if let days = cycle.daysUntilDue(reference: ref) {
            XCTAssertLessThan(days, 0)
        }
    }
}
