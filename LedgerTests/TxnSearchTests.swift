import XCTest
import Foundation
@testable import Ledger

final class TxnSearchTests: XCTestCase {
    private let bookId = UUID()
    private let accountId = UUID()
    private let otherAccountId = UUID()
    private let categoryId = UUID()

    private func makeTxn(
        _ type: TxnType = .expense,
        amount: Int64 = 3800,
        note: String? = nil,
        payee: String? = nil,
        account: UUID? = nil,
        category: UUID? = nil,
        occurredAt: Date = Date(),
        counterAccount: UUID? = nil
    ) -> Txn {
        Txn(
            bookId: bookId,
            type: type,
            amountMinor: amount,
            accountId: account ?? accountId,
            occurredAt: occurredAt,
            categoryId: category,
            counterAccountId: counterAccount
        )
    }

    func testKeywordMatchesNotePayeeCategoryAccountAndAmount() {
        let txn = makeTxn(amount: 3800, note: "午餐", payee: "星巴克", category: categoryId)
        XCTAssertTrue(TxnSearchCriteria(keyword: "午餐").matches(txn, categoryName: "餐饮", accountName: "招行"))
        XCTAssertTrue(TxnSearchCriteria(keyword: "星巴克").matches(txn, categoryName: "餐饮", accountName: "招行"))
        XCTAssertTrue(TxnSearchCriteria(keyword: "餐饮").matches(txn, categoryName: "餐饮", accountName: "招行"))
        XCTAssertTrue(TxnSearchCriteria(keyword: "招行").matches(txn, categoryName: "餐饮", accountName: "招行"))
        XCTAssertTrue(TxnSearchCriteria(keyword: "38.00").matches(txn, categoryName: nil, accountName: nil))
        XCTAssertFalse(TxnSearchCriteria(keyword: "打车").matches(txn, categoryName: "餐饮", accountName: "招行"))
    }

    func testTypeFilter() {
        let expense = makeTxn(.expense)
        let income = makeTxn(.income)
        let criteria = TxnSearchCriteria(types: [.income])
        XCTAssertFalse(criteria.matches(expense, categoryName: nil, accountName: nil))
        XCTAssertTrue(criteria.matches(income, categoryName: nil, accountName: nil))
    }

    func testAmountRange() {
        let small = makeTxn(amount: 5_000)
        let large = makeTxn(amount: 120_000)
        let criteria = TxnSearchCriteria(minAmountMinor: 10_000, maxAmountMinor: 200_000)
        XCTAssertFalse(criteria.matches(small, categoryName: nil, accountName: nil))
        XCTAssertTrue(criteria.matches(large, categoryName: nil, accountName: nil))
    }

    func testReimbursableAndRefundFlags() {
        let reimbursable = makeTxn()
        reimbursable.isReimbursable = true
        let normal = makeTxn()

        XCTAssertTrue(TxnSearchCriteria(onlyReimbursable: true).matches(reimbursable, categoryName: nil, accountName: nil))
        XCTAssertFalse(TxnSearchCriteria(onlyReimbursable: true).matches(normal, categoryName: nil, accountName: nil))

        let refund = makeTxn(.income, amount: 1000)
        refund.refundOfTxnId = UUID()
        XCTAssertTrue(TxnSearchCriteria(onlyRefunds: true).matches(refund, categoryName: nil, accountName: nil))
        XCTAssertFalse(TxnSearchCriteria(onlyRefunds: true).matches(normal, categoryName: nil, accountName: nil))
    }

    func testDateScopeThisMonthExcludesOldTransactions() {
        let currentStart = AppCalendar.startOfMonth(Date())
        let lastMonth = AppCalendar.gregorian.date(byAdding: .day, value: -1, to: currentStart)
        let old = makeTxn(occurredAt: lastMonth ?? currentStart.addingTimeInterval(-86_400))
        let today = makeTxn(occurredAt: Date())

        let criteria = TxnSearchCriteria(dateScope: .thisMonth)
        XCTAssertFalse(criteria.matches(old, categoryName: nil, accountName: nil))
        XCTAssertTrue(criteria.matches(today, categoryName: nil, accountName: nil))
    }

    func testAccountFilterIncludesCounterAccount() {
        let transfer = makeTxn(.transfer, account: accountId, counterAccount: otherAccountId)
        XCTAssertTrue(TxnSearchCriteria(accountId: accountId).matches(transfer, categoryName: nil, accountName: nil))
        XCTAssertTrue(TxnSearchCriteria(accountId: otherAccountId).matches(transfer, categoryName: nil, accountName: nil))
        XCTAssertFalse(TxnSearchCriteria(accountId: UUID()).matches(transfer, categoryName: nil, accountName: nil))
    }

    func testIsActiveReflectsConditions() {
        XCTAssertFalse(TxnSearchCriteria().isActive)
        XCTAssertTrue(TxnSearchCriteria(keyword: "咖啡").isActive)
        XCTAssertTrue(TxnSearchCriteria(dateScope: .thisYear).isActive)
        XCTAssertTrue(TxnSearchCriteria(minAmountMinor: 1000).isActive)
    }
}
