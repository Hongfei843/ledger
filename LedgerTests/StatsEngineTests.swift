import XCTest
import Foundation
@testable import Ledger

final class StatsEngineTests: XCTestCase {
    private let bookId = UUID()
    private let accountId = UUID()

    private func currentRange() -> DateInterval {
        AppCalendar.monthInterval(containing: Date())
    }

    private func makeDraftClaim() -> Claim {
        let claim = Claim(bookId: bookId, title: "测试报销", periodMonth: AppCalendar.monthKey(Date()))
        claim.status = .draft
        return claim
    }

    /// B 口径：待报销支出应从个人支出中剔除
    func testPersonalCaliberExcludesPendingReimbursement() {
        let claim = makeDraftClaim()
        let normal = Txn(bookId: bookId, type: .expense, amountMinor: 1000, accountId: accountId)
        let reimbursable = Txn(bookId: bookId, type: .expense, amountMinor: 5000, accountId: accountId)
        reimbursable.isReimbursable = true
        reimbursable.claimId = claim.id

        let personal = StatsEngine.summary(
            range: currentRange(),
            caliber: .personal,
            txns: [normal, reimbursable],
            claims: [claim]
        )
        let cashFlow = StatsEngine.summary(
            range: currentRange(),
            caliber: .cashFlow,
            txns: [normal, reimbursable],
            claims: [claim]
        )

        XCTAssertEqual(personal.expenseMinor, 1000)
        XCTAssertEqual(personal.pendingMinor, 5000)
        XCTAssertEqual(cashFlow.expenseMinor, 6000)
        // 核心不变式：现金流口径 − 个人口径 == 待报销
        XCTAssertEqual(cashFlow.expenseMinor - personal.expenseMinor, personal.pendingMinor)
    }

    /// 报销到账不算个人收入
    func testReimbursementIncomeIsNotPersonalIncome() {
        let claim = makeDraftClaim()
        claim.status = .reimbursed
        let income = Txn(bookId: bookId, type: .income, amountMinor: 5000, accountId: accountId)
        income.claimId = claim.id

        let personal = StatsEngine.summary(range: currentRange(), caliber: .personal, txns: [income], claims: [claim])
        let cashFlow = StatsEngine.summary(range: currentRange(), caliber: .cashFlow, txns: [income], claims: [claim])

        XCTAssertEqual(personal.incomeMinor, 0)
        XCTAssertEqual(cashFlow.incomeMinor, 5000)
        XCTAssertEqual(cashFlow.incomeMinor - personal.incomeMinor, 5000)
    }

    /// 报销单关闭后，垫付金额回到个人支出
    func testClosedClaimCountsBackAsExpense() {
        let claim = makeDraftClaim()
        claim.status = .closed
        let reimbursable = Txn(bookId: bookId, type: .expense, amountMinor: 3000, accountId: accountId)
        reimbursable.isReimbursable = true
        reimbursable.claimId = claim.id

        let personal = StatsEngine.summary(
            range: currentRange(),
            caliber: .personal,
            txns: [reimbursable],
            claims: [claim]
        )
        XCTAssertEqual(personal.expenseMinor, 3000)
        XCTAssertEqual(personal.pendingMinor, 0)
    }

    /// 转账、余额调整不进收支
    func testTransferAndAdjustmentExcluded() {
        let transfer = Txn(bookId: bookId, type: .transfer, amountMinor: 20000, accountId: UUID(), counterAccountId: accountId)
        let adjustment = Txn(bookId: bookId, type: .adjustment, amountMinor: 500, accountId: accountId)

        let cashFlow = StatsEngine.summary(range: currentRange(), caliber: .cashFlow, txns: [transfer, adjustment], claims: [])
        XCTAssertEqual(cashFlow.expenseMinor, 0)
        XCTAssertEqual(cashFlow.incomeMinor, 0)
    }

    func testCategoryGrouping() {
        let food = Category(bookId: bookId, name: "餐饮", kind: .expense, iconEmoji: "🍜")
        let traffic = Category(bookId: bookId, name: "交通", kind: .expense, iconEmoji: "🚇")

        let a = Txn(bookId: bookId, type: .expense, amountMinor: 2000, accountId: accountId, categoryId: food.id)
        let b = Txn(bookId: bookId, type: .expense, amountMinor: 3000, accountId: accountId, categoryId: food.id)
        let c = Txn(bookId: bookId, type: .expense, amountMinor: 1000, accountId: accountId, categoryId: traffic.id)

        let slices = StatsEngine.byCategory(
            range: currentRange(),
            caliber: .personal,
            txns: [a, b, c],
            claims: [],
            categories: [food, traffic]
        )

        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices[0].name, "餐饮")
        XCTAssertEqual(slices[0].amountMinor, 5000)
        XCTAssertEqual(slices[0].count, 2)
        XCTAssertEqual(slices[1].name, "交通")
    }
}
