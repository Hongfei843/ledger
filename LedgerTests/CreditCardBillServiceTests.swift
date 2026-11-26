import XCTest
import Foundation
@testable import Ledger

final class CreditCardBillServiceTests: XCTestCase {
    private let bookId = UUID()
    private var calendar: Calendar { AppCalendar.gregorian }

    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)) ?? Date()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? reference
    }

    private func makeCard() -> Account {
        let account = Account(bookId: bookId, name: "招行信用卡", type: .credit)
        account.billDay = 10
        account.dueDay = 20
        return account
    }

    func testInfoCycleDatesAndPeriodMonth() {
        let card = makeCard()
        let info = CreditCardBillService.info(for: card, txns: [], statements: [], reference: reference)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.periodMonth, "2026-03")
        XCTAssertEqual(calendar.startOfDay(for: info?.billDate ?? reference), calendar.startOfDay(for: date(2026, 3, 10)))
        XCTAssertEqual(calendar.startOfDay(for: info?.dueDate ?? reference), calendar.startOfDay(for: date(2026, 3, 20)))
        XCTAssertEqual(calendar.startOfDay(for: info?.statementPeriod.start ?? reference), calendar.startOfDay(for: date(2026, 2, 11)))
    }

    func testEstimateNetsRefundAndIgnoresOutOfPeriod() {
        let card = makeCard()
        let expenseIn = Txn(bookId: bookId, type: .expense, amountMinor: 60_000, accountId: card.id, occurredAt: date(2026, 2, 20))
        let expenseOut = Txn(bookId: bookId, type: .expense, amountMinor: 99_000, accountId: card.id, occurredAt: date(2026, 1, 5))
        let refund = Txn(bookId: bookId, type: .income, amountMinor: 10_000, accountId: card.id, occurredAt: date(2026, 2, 25))
        refund.refundOfTxnId = expenseIn.id

        let info = CreditCardBillService.info(
            for: card,
            txns: [expenseIn, expenseOut, refund],
            statements: [],
            reference: reference
        )
        XCTAssertEqual(info?.estimatedAmountMinor, 50_000)
    }

    func testRegisteredStatementSurfacedEarliestFirst() {
        let card = makeCard()
        let later = Statement(accountId: card.id, periodMonth: "2026-03", billAmountMinor: 80_000, minimumPaymentMinor: 8_000, dueDate: date(2026, 3, 20))
        let earlier = Statement(accountId: card.id, periodMonth: "2026-02", billAmountMinor: 30_000, minimumPaymentMinor: 3_000, dueDate: date(2026, 2, 20))
        let settled = Statement(accountId: card.id, periodMonth: "2026-01", billAmountMinor: 10_000, minimumPaymentMinor: 1_000, dueDate: date(2026, 1, 20))
        settled.paidAmountMinor = 10_000
        settled.refreshStatus()

        let info = CreditCardBillService.info(
            for: card,
            txns: [],
            statements: [later, earlier, settled],
            reference: reference
        )
        XCTAssertEqual(info?.registered?.id, earlier.id)
    }

    func testNoCycleWithoutBillDays() {
        let plain = Account(bookId: bookId, name: "普通卡", type: .credit)
        XCTAssertNil(CreditCardBillService.info(for: plain, txns: [], statements: [], reference: reference))
    }

    func testEstimateZeroWhenNothingSpent() {
        let card = makeCard()
        let info = CreditCardBillService.info(for: card, txns: [], statements: [], reference: reference)
        XCTAssertEqual(info?.estimatedAmountMinor, 0)
    }
}
