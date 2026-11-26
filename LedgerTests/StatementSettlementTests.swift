import XCTest
import Foundation
@testable import Ledger

final class StatementSettlementTests: XCTestCase {
    private let bookId = UUID()
    private var calendar: Calendar { AppCalendar.gregorian }
    private let accountId = UUID()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    private func makeStatement(_ amount: Int64, dueDay: Int, month: Int = 3, paid: Int64 = 0) -> Statement {
        let statement = Statement(
            accountId: accountId,
            periodMonth: String(format: "2026-%02d", month),
            billAmountMinor: amount,
            minimumPaymentMinor: amount / 10,
            dueDate: date(2026, month, dueDay)
        )
        statement.paidAmountMinor = paid
        return statement
    }

    func testAllocateOldestFirst() {
        let first = makeStatement(30_000, dueDay: 10)
        let second = makeStatement(20_000, dueDay: 20)

        let allocations = StatementSettlementService.allocate(paymentMinor: 40_000, statements: [second, first])
        XCTAssertEqual(allocations.count, 2)
        XCTAssertEqual(allocations[0].statementId, first.id)
        XCTAssertEqual(allocations[0].appliedMinor, 30_000)
        XCTAssertEqual(allocations[1].statementId, second.id)
        XCTAssertEqual(allocations[1].appliedMinor, 10_000)
    }

    func testPartialPaymentOnlyTouchesFirst() {
        let first = makeStatement(30_000, dueDay: 10)
        let second = makeStatement(20_000, dueDay: 20)

        let allocations = StatementSettlementService.allocate(paymentMinor: 10_000, statements: [first, second])
        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocations.first?.statementId, first.id)
        XCTAssertEqual(allocations.first?.appliedMinor, 10_000)
    }

    func testOverpayReturnsLeftover() {
        let first = makeStatement(30_000, dueDay: 10)
        let second = makeStatement(20_000, dueDay: 20)

        let leftover = StatementSettlementService.apply(paymentMinor: 100_000, statements: [first, second], at: date(2026, 3, 15))
        XCTAssertEqual(leftover, 50_000)
        XCTAssertEqual(first.outstandingMinor, 0)
        XCTAssertEqual(second.outstandingMinor, 0)
    }

    func testSettledAndDeletedStatementsIgnored() {
        let settled = makeStatement(30_000, dueDay: 10, paid: 30_000)
        settled.refreshStatus()
        let deleted = makeStatement(20_000, dueDay: 20)
        deleted.deletedAt = Date()
        let live = makeStatement(5_000, dueDay: 25)

        let allocations = StatementSettlementService.allocate(paymentMinor: 50_000, statements: [settled, deleted, live])
        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocations.first?.statementId, live.id)
    }

    func testApplyUpdatesStatusAndPaidAt() {
        let statement = makeStatement(30_000, dueDay: 10)
        let payDate = date(2026, 3, 15)

        let leftover = StatementSettlementService.apply(paymentMinor: 30_000, statements: [statement], at: payDate)
        XCTAssertEqual(leftover, 0)
        XCTAssertEqual(statement.paidAmountMinor, 30_000)
        XCTAssertEqual(statement.status, .paid)
        XCTAssertNotNil(statement.paidAt)
    }

    func testApplyPartialKeepsIssuedStatus() {
        let statement = makeStatement(30_000, dueDay: 10)
        _ = StatementSettlementService.apply(paymentMinor: 10_000, statements: [statement], at: date(2026, 3, 15))
        XCTAssertEqual(statement.paidAmountMinor, 10_000)
        XCTAssertEqual(statement.status, .partial)
        XCTAssertEqual(statement.outstandingMinor, 20_000)
    }
}
