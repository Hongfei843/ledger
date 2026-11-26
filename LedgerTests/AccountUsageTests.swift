import XCTest
import Foundation
@testable import Ledger

final class AccountUsageTests: XCTestCase {
    private let bookId = UUID()

    private func makeAccount(_ name: String, sortOrder: Int = 0) -> Account {
        Account(bookId: bookId, name: name, type: .debit, sortOrder: sortOrder)
    }

    func testUsageCountsIncludeBothTransferSidesAndIgnoreDeleted() {
        let a = makeAccount("A")
        let b = makeAccount("B")
        let normal = Txn(bookId: bookId, type: .expense, amountMinor: 1000, accountId: a.id)
        let transfer = Txn(bookId: bookId, type: .transfer, amountMinor: 2000, accountId: a.id, counterAccountId: b.id)
        let deleted = Txn(bookId: bookId, type: .expense, amountMinor: 3000, accountId: b.id)
        deleted.deletedAt = Date()

        let usage = AccountUsageService.usageCounts(txns: [normal, transfer, deleted])
        XCTAssertEqual(usage[a.id], 2)
        XCTAssertEqual(usage[b.id], 1)
    }

    func testOrderedByUsageThenSortOrderThenName() {
        let often = makeAccount("常用", sortOrder: 5)
        let rare = makeAccount("少用", sortOrder: 1)
        let tieA = makeAccount("A卡", sortOrder: 2)
        let tieB = makeAccount("B卡", sortOrder: 2)

        let usage = [often.id: 10, rare.id: 1, tieA.id: 0, tieB.id: 0]
        let ordered = AccountUsageService.orderedAccounts([rare, tieB, often, tieA], usage: usage)

        XCTAssertEqual(ordered.map { $0.name }, ["常用", "少用", "A卡", "B卡"])
    }

    func testBalanceMapMatchesBalanceService() {
        let cash = makeAccount("现金")
        cash.openingBalanceMinor = 100_000
        let expense = Txn(bookId: bookId, type: .expense, amountMinor: 20_000, accountId: cash.id)

        let map = AccountUsageService.balanceMap(accounts: [cash], txns: [expense])
        XCTAssertEqual(map[cash.id], 80_000)
    }

    func testSubtitleForCreditLiabilityAndAsset() {
        let debit = makeAccount("储蓄卡")
        XCTAssertEqual(AccountUsageService.subtitle(account: debit, balanceMinor: 123_400), "余额 ¥1,234.00")

        let credit = Account(bookId: bookId, name: "信用卡", type: .credit)
        credit.creditLimitMinor = 500_000
        XCTAssertEqual(AccountUsageService.subtitle(account: credit, balanceMinor: -100_000), "可用 ¥4,000.00")

        let loan = Account(bookId: bookId, name: "消费贷", type: .loan)
        XCTAssertEqual(AccountUsageService.subtitle(account: loan, balanceMinor: -50_000), "欠 ¥500.00")
    }
}
