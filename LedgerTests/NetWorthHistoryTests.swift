import XCTest
import Foundation
@testable import Ledger

final class NetWorthHistoryTests: XCTestCase {
    private let bookId = UUID()

    private func makeAccount(
        _ type: AccountType,
        opening: Int64,
        include: Bool = true,
        archived: Bool = false,
        deleted: Bool = false
    ) -> Account {
        let account = Account(bookId: bookId, name: type.displayName, type: type, openingBalanceMinor: opening)
        account.includeInNetWorth = include
        account.isArchived = archived
        if deleted { account.deletedAt = Date() }
        return account
    }

    private func previousMonthDate() -> Date {
        let currentStart = AppCalendar.startOfMonth(Date())
        let previousStart = AppCalendar.gregorian.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
        return AppCalendar.gregorian.date(byAdding: .day, value: 1, to: previousStart) ?? previousStart
    }

    func testEmptyAccountsProduceZeroPoints() {
        let points = NetWorthHistory.monthly(months: 3, accounts: [], transactions: [])
        XCTAssertEqual(points.count, 3)
        XCTAssertTrue(points.allSatisfy { $0.netWorthMinor == 0 })
        XCTAssertEqual(points.last?.assetsMinor, 0)
        XCTAssertEqual(points.last?.liabilitiesMinor, 0)
    }

    func testExpenseLowersLaterPointsOnly() {
        let cash = makeAccount(.debit, opening: 100_000)
        let expense = Txn(bookId: bookId, type: .expense, amountMinor: 20_000, accountId: cash.id, occurredAt: previousMonthDate())

        let points = NetWorthHistory.monthly(months: 3, accounts: [cash], transactions: [expense])
        XCTAssertEqual(points.count, 3)
        // 两个月前的月末：这笔支出还没发生
        XCTAssertEqual(points[0].netWorthMinor, 100_000)
        // 上个月末与现在：已经发生
        XCTAssertEqual(points[1].netWorthMinor, 80_000)
        XCTAssertEqual(points[2].netWorthMinor, 80_000)
    }

    func testCreditAccountCountsAsLiability() {
        let cash = makeAccount(.debit, opening: 100_000)
        let credit = makeAccount(.credit, opening: -30_000)

        let points = NetWorthHistory.monthly(months: 1, accounts: [cash, credit], transactions: [])
        XCTAssertEqual(points.first?.assetsMinor, 100_000)
        XCTAssertEqual(points.first?.liabilitiesMinor, 30_000)
        XCTAssertEqual(points.first?.netWorthMinor, 70_000)
    }

    func testLoanArchivedAndDeletedAccountsExcluded() {
        let cash = makeAccount(.debit, opening: 50_000)
        let loan = makeAccount(.loan, opening: -200_000)
        let archived = makeAccount(.debit, opening: 90_000, archived: true)
        let deleted = makeAccount(.debit, opening: 70_000, deleted: true)
        let excluded = makeAccount(.debit, opening: 30_000, include: false)

        let points = NetWorthHistory.monthly(
            months: 1,
            accounts: [cash, loan, archived, deleted, excluded],
            transactions: []
        )
        XCTAssertEqual(points.first?.netWorthMinor, 50_000)
        XCTAssertEqual(points.first?.liabilitiesMinor, 0)
    }

    func testTransferMovesValueWithoutChangingNetWorth() {
        let cash = makeAccount(.debit, opening: 100_000)
        let wallet = makeAccount(.ewallet, opening: 0)
        let transfer = Txn(
            bookId: bookId,
            type: .transfer,
            amountMinor: 30_000,
            accountId: cash.id,
            occurredAt: previousMonthDate(),
            counterAccountId: wallet.id
        )

        let points = NetWorthHistory.monthly(months: 1, accounts: [cash, wallet], transactions: [transfer])
        XCTAssertEqual(points.first?.netWorthMinor, 100_000)
    }
}
