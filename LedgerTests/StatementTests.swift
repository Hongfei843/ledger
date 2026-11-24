import XCTest
import Foundation
@testable import Ledger

final class StatementTests: XCTestCase {
    private let calendar = AppCalendar.gregorian

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return calendar.date(from: comps)!
    }

    private func makeStatement(due: Date, amount: Int64 = 5000_00) -> Statement {
        Statement(
            accountId: UUID(),
            periodMonth: "2026-11",
            billAmountMinor: amount,
            minimumPaymentMinor: 500_00,
            dueDate: due
        )
    }

    func testOutstanding() {
        let statement = makeStatement(due: date(2026, 11, 25))
        XCTAssertEqual(statement.outstandingMinor, 5000_00)
        statement.paidAmountMinor = 2000_00
        XCTAssertEqual(statement.outstandingMinor, 3000_00)
        statement.paidAmountMinor = 6000_00
        XCTAssertEqual(statement.outstandingMinor, 0, "超还不应为负")
    }

    func testStatusPaid() {
        let statement = makeStatement(due: date(2026, 11, 25))
        statement.paidAmountMinor = 5000_00
        statement.refreshStatus(reference: date(2026, 11, 20), calendar: calendar)
        XCTAssertEqual(statement.status, .paid)
        XCTAssertNotNil(statement.paidAt)
    }

    func testStatusPartial() {
        let statement = makeStatement(due: date(2026, 11, 25))
        statement.paidAmountMinor = 1000_00
        statement.refreshStatus(reference: date(2026, 11, 20), calendar: calendar)
        XCTAssertEqual(statement.status, .partial)
    }

    func testStatusOverdue() {
        let statement = makeStatement(due: date(2026, 11, 25))
        statement.refreshStatus(reference: date(2026, 11, 28), calendar: calendar)
        XCTAssertEqual(statement.status, .overdue)
    }

    func testStatusIssuedBeforeDue() {
        let statement = makeStatement(due: date(2026, 11, 25))
        statement.refreshStatus(reference: date(2026, 11, 20), calendar: calendar)
        XCTAssertEqual(statement.status, .issued)
    }
}
