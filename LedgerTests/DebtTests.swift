import XCTest
import Foundation
@testable import Ledger

final class DebtTests: XCTestCase {
    private let bookId = UUID()

    private func make(_ direction: DebtDirection, _ amount: Int64) -> Debt {
        Debt(bookId: bookId, direction: direction, counterparty: "张三", amountMinor: amount)
    }

    func testSummaryCountsOnlyOpen() {
        let a = make(.lend, 100_00)
        let b = make(.lend, 50_00)
        let c = make(.borrow, 30_00)
        let settled = make(.lend, 999_00)
        settled.isSettled = true

        let result = DebtService.summary([a, b, c, settled])
        XCTAssertEqual(result.receivable, 150_00)
        XCTAssertEqual(result.payable, 30_00)
    }

    func testDeletedIgnored() {
        let a = make(.lend, 100_00)
        a.deletedAt = Date()
        let result = DebtService.summary([a])
        XCTAssertEqual(result.receivable, 0)
    }

    func testOverdue() {
        let debt = make(.lend, 100_00)
        debt.dueDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())
        XCTAssertTrue(debt.isOverdue())

        debt.isSettled = true
        XCTAssertFalse(debt.isOverdue(), "已结清不算逾期")
    }
}
