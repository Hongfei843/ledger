import XCTest
import Foundation
@testable import Ledger

final class BalanceTests: XCTestCase {
    private func makeAccount(opening: Int64 = 0, type: AccountType = .debit) -> Account {
        Account(bookId: UUID(), name: "测试", type: type, openingBalanceMinor: opening)
    }

    func testExpenseAndIncome() {
        let account = makeAccount(opening: 100000)
        let expense = Txn(bookId: UUID(), type: .expense, amountMinor: 2000, accountId: account.id)
        let income = Txn(bookId: UUID(), type: .income, amountMinor: 5000, accountId: account.id)

        let balance = BalanceService.balance(
            of: account,
            transactions: [expense, income],
            openingBalanceMinor: account.openingBalanceMinor
        )
        XCTAssertEqual(balance, 103000)
    }

    func testTransferMovesMoney() {
        let from = makeAccount(opening: 100000)
        let to = makeAccount(opening: 0)

        let transfer = Txn(
            bookId: UUID(),
            type: .transfer,
            amountMinor: 30000,
            accountId: from.id,
            counterAccountId: to.id
        )

        XCTAssertEqual(
            BalanceService.balance(of: from, transactions: [transfer], openingBalanceMinor: from.openingBalanceMinor),
            70000
        )
        XCTAssertEqual(
            BalanceService.balance(of: to, transactions: [transfer], openingBalanceMinor: to.openingBalanceMinor),
            30000
        )
    }

    /// 信用卡还款：从储蓄卡转账到信用卡，负债减少，不产生支出
    func testCreditCardRepaymentIsNotExpense() {
        let debit = makeAccount(opening: 100000)
        let credit = makeAccount(opening: -50000, type: .credit)

        let repayment = Txn(
            bookId: UUID(),
            type: .transfer,
            amountMinor: 50000,
            accountId: debit.id,
            counterAccountId: credit.id
        )

        XCTAssertEqual(
            BalanceService.balance(of: credit, transactions: [repayment], openingBalanceMinor: credit.openingBalanceMinor),
            0
        )
        XCTAssertEqual(repayment.type, .transfer)
        XCTAssertFalse(repayment.type.countsAsCashFlow)
    }

    func testDeletedTransactionsAreIgnored() {
        let account = makeAccount(opening: 10000)
        let txn = Txn(bookId: UUID(), type: .expense, amountMinor: 1000, accountId: account.id)
        txn.deletedAt = Date()

        let balance = BalanceService.balance(
            of: account,
            transactions: [txn],
            openingBalanceMinor: account.openingBalanceMinor
        )
        XCTAssertEqual(balance, 10000)
    }

    func testTotalsAreConsistentAndScopedToBook() {
        let bookA = UUID()
        let bookB = UUID()
        let cash = Account(bookId: bookA, name: "现金", type: .cash, openingBalanceMinor: 10_000)
        let credit = Account(bookId: bookA, name: "信用卡", type: .credit, openingBalanceMinor: -3_000)
        let excluded = Account(bookId: bookA, name: "专用", type: .cash, openingBalanceMinor: 99_000)
        excluded.includeInNetWorth = false
        let otherBook = Account(bookId: bookB, name: "其他账本", type: .cash, openingBalanceMinor: 50_000)
        let loan = Account(bookId: bookA, name: "房贷", type: .loan, openingBalanceMinor: -500_000, isSystem: true)

        let totals = BalanceService.totals(
            accounts: [cash, credit, excluded, otherBook, loan],
            transactions: [],
            bookId: bookA
        )
        XCTAssertEqual(totals.assetsMinor, 10_000)
        XCTAssertEqual(totals.liabilitiesMinor, 3_000)
        XCTAssertEqual(totals.netWorthMinor, 7_000)
        XCTAssertEqual(totals.assetsMinor - totals.liabilitiesMinor, totals.netWorthMinor)
    }

    func testCreditOverpaymentCountsAsAssetInsteadOfLiability() {
        let credit = Account(bookId: UUID(), name: "信用卡", type: .credit, openingBalanceMinor: 500)
        let totals = BalanceService.totals(accounts: [credit], transactions: [])
        XCTAssertEqual(totals.assetsMinor, 500)
        XCTAssertEqual(totals.liabilitiesMinor, 0)
        XCTAssertEqual(totals.netWorthMinor, 500)
    }

    func testLiabilityActualDebtAndSignedBalanceConversion() {
        XCTAssertEqual(BalanceService.signedBalance(fromActualInput: 1_200, accountType: .credit), -1_200)
        XCTAssertEqual(BalanceService.signedBalance(fromActualInput: -200, accountType: .credit), 200)
        XCTAssertEqual(BalanceService.displayBalance(-1_200, accountType: .credit), 1_200)
        XCTAssertEqual(BalanceService.displayBalance(1_200, accountType: .cash), 1_200)
    }
}
