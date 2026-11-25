import XCTest
import Foundation
@testable import Ledger

/// 退款闭环：退款挂在原支出上，统计里冲减支出、不算收入。
final class RefundTests: XCTestCase {
    private let bookId = UUID()
    private let accountId = UUID()

    private func makeExpense(_ amount: Int64, categoryId: UUID? = nil) -> Txn {
        Txn(bookId: bookId, type: .expense, amountMinor: amount, accountId: accountId, categoryId: categoryId)
    }

    private func makeRefund(of original: Txn, amount: Int64) -> Txn {
        let refund = Txn(
            bookId: bookId,
            type: .income,
            amountMinor: amount,
            accountId: accountId,
            categoryId: original.categoryId
        )
        refund.refundOfTxnId = original.id
        return refund
    }

    private func currentRange() -> DateInterval {
        AppCalendar.monthInterval(containing: Date())
    }

    func testRefundedAndRemaining() {
        let expense = makeExpense(10000)
        let first = makeRefund(of: expense, amount: 3000)
        let second = makeRefund(of: expense, amount: 2000)
        let all = [expense, first, second]

        XCTAssertEqual(RefundService.refundedMinor(of: expense, all: all), 5000)
        XCTAssertEqual(RefundService.remainingRefundableMinor(of: expense, all: all), 5000)
        XCTAssertEqual(RefundService.refunds(of: expense, all: all).count, 2)
    }

    func testDeletedRefundIgnored() {
        let expense = makeExpense(10000)
        let refund = makeRefund(of: expense, amount: 4000)
        refund.deletedAt = Date()

        XCTAssertEqual(RefundService.refundedMinor(of: expense, all: [expense, refund]), 0)
        XCTAssertEqual(RefundService.remainingRefundableMinor(of: expense, all: [expense, refund]), 10000)
    }

    func testFullRefundRemovesExpenseAndIncome() {
        let expense = makeExpense(10000)
        let refund = makeRefund(of: expense, amount: 10000)

        let summary = StatsEngine.summary(
            range: currentRange(),
            caliber: .cashFlow,
            txns: [expense, refund],
            claims: []
        )

        XCTAssertEqual(summary.incomeMinor, 0, "退款不算收入")
        XCTAssertEqual(summary.expenseMinor, 0, "全额退款后支出为 0")
        XCTAssertEqual(summary.balanceMinor, 0)
    }

    func testPartialRefundNetsExpense() {
        let expense = makeExpense(10000)
        let refund = makeRefund(of: expense, amount: 3000)

        let cashFlow = StatsEngine.summary(
            range: currentRange(),
            caliber: .cashFlow,
            txns: [expense, refund],
            claims: []
        )
        let personal = StatsEngine.summary(
            range: currentRange(),
            caliber: .personal,
            txns: [expense, refund],
            claims: []
        )

        XCTAssertEqual(cashFlow.expenseMinor, 7000)
        XCTAssertEqual(cashFlow.incomeMinor, 0)
        XCTAssertEqual(personal.expenseMinor, 7000)
    }

    func testRefundClampsAtZero() {
        // 异常数据：退款金额大于原支出，也不能把支出冲成负数
        let expense = makeExpense(1000)
        let refund = makeRefund(of: expense, amount: 3000)

        let summary = StatsEngine.summary(
            range: currentRange(),
            caliber: .cashFlow,
            txns: [expense, refund],
            claims: []
        )

        XCTAssertEqual(summary.expenseMinor, 0)
        XCTAssertEqual(summary.incomeMinor, 0)
    }

    func testCategoryNettedByRefund() {
        let food = Category(bookId: bookId, name: "餐饮", kind: .expense, iconEmoji: "🍜")
        let traffic = Category(bookId: bookId, name: "交通", kind: .expense, iconEmoji: "🚇")
        let first = makeExpense(8000, categoryId: food.id)
        let second = makeExpense(2000, categoryId: food.id)
        let refund = makeRefund(of: first, amount: 3000)

        let slices = StatsEngine.byCategory(
            range: currentRange(),
            caliber: .personal,
            txns: [first, second, refund],
            claims: [],
            categories: [food, traffic]
        )

        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices.first?.name, "餐饮")
        XCTAssertEqual(slices.first?.amountMinor, 7000)
        XCTAssertEqual(slices.first?.count, 2)
    }

    func testMonthlyTrendNetsRefund() {
        let expense = makeExpense(10000)
        let refund = makeRefund(of: expense, amount: 2500)

        let buckets = StatsEngine.byMonth(months: 6, endingAt: Date(), txns: [expense, refund])
        let current = buckets.last

        XCTAssertEqual(current?.expenseMinor, 7500)
        XCTAssertEqual(current?.incomeMinor, 0)
    }
}
