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
}
