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

    func testRefundOfPendingReimbursementDoesNotReducePersonalExpense() {
        let claim = makeDraftClaim()
        let original = Txn(bookId: bookId, type: .expense, amountMinor: 5_000, accountId: accountId)
        original.isReimbursable = true
        original.claimId = claim.id
        let refund = Txn(bookId: bookId, type: .income, amountMinor: 2_000, accountId: accountId)
        refund.refundOfTxnId = original.id

        let personal = StatsEngine.summary(
            range: currentRange(),
            caliber: .personal,
            txns: [original, refund],
            claims: [claim]
        )
        let cashFlow = StatsEngine.summary(
            range: currentRange(),
            caliber: .cashFlow,
            txns: [original, refund],
            claims: [claim]
        )
        XCTAssertEqual(personal.expenseMinor, 0)
        XCTAssertEqual(personal.pendingMinor, 3_000)
        XCTAssertEqual(cashFlow.expenseMinor, 3_000)
    }

    func testReimbursedClaimOnlyCountsShortfallAsPersonalExpense() {
        let claim = makeDraftClaim()
        claim.status = .reimbursed
        let original = Txn(bookId: bookId, type: .expense, amountMinor: 5_000, accountId: accountId)
        original.isReimbursable = true
        original.claimId = claim.id
        let income = Txn(bookId: bookId, type: .income, amountMinor: 3_000, accountId: accountId)
        income.claimId = claim.id
        let shortfall = Txn(
            bookId: bookId,
            type: .expense,
            amountMinor: 2_000,
            accountId: accountId,
            source: .reimbursement
        )
        shortfall.claimId = claim.id

        let all = [original, income, shortfall]
        let personal = StatsEngine.summary(range: currentRange(), caliber: .personal, txns: all, claims: [claim])
        let cashFlow = StatsEngine.summary(range: currentRange(), caliber: .cashFlow, txns: all, claims: [claim])
        let advance = StatsEngine.summary(range: currentRange(), caliber: .advance, txns: all, claims: [claim])

        XCTAssertEqual(personal.expenseMinor, 2_000)
        XCTAssertEqual(personal.incomeMinor, 0)
        XCTAssertEqual(cashFlow.expenseMinor, 5_000)
        XCTAssertEqual(cashFlow.incomeMinor, 3_000)
        XCTAssertEqual(advance.expenseMinor, 5_000)
        XCTAssertEqual(advance.incomeMinor, 3_000)
    }

    func testMonthlyTrendUsesSelectedCaliber() {
        let claim = makeDraftClaim()
        let normal = Txn(bookId: bookId, type: .expense, amountMinor: 1_000, accountId: accountId)
        let pending = Txn(bookId: bookId, type: .expense, amountMinor: 4_000, accountId: accountId)
        pending.isReimbursable = true
        pending.claimId = claim.id

        let buckets = StatsEngine.byMonth(
            months: 1,
            endingAt: Date(),
            txns: [normal, pending],
            claims: [claim],
            caliber: .personal
        )
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].expenseMinor, 1_000)
    }

    /// 次月才发生的退款，不能倒回来改写本月「待报销」
    func testPendingNotReducedByRefundInLaterMonth() {
        let claim = makeDraftClaim()
        let original = Txn(bookId: bookId, type: .expense, amountMinor: 5_000, accountId: accountId)
        original.isReimbursable = true
        original.claimId = claim.id

        let nextMonth = AppCalendar.startOfNextMonth(Date())
        let refund = Txn(bookId: bookId, type: .income, amountMinor: 2_000, accountId: accountId, occurredAt: nextMonth.addingTimeInterval(86_400))
        refund.refundOfTxnId = original.id

        let summary = StatsEngine.summary(
            range: currentRange(),
            caliber: .personal,
            txns: [original, refund],
            claims: [claim]
        )
        XCTAssertEqual(summary.pendingMinor, 5_000)
    }

    /// 跨月退款：分类合计 + 差额必须等于主卡净支出，不能凭空消失
    func testCrossMonthRefundKeepsBreakdownConsistent() {
        let food = Category(bookId: bookId, name: "餐饮", kind: .expense)
        let traffic = Category(bookId: bookId, name: "交通", kind: .expense)
        let lastMonth = AppCalendar.gregorian.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let lastMonthExpense = Txn(bookId: bookId, type: .expense, amountMinor: 5_000, accountId: accountId, occurredAt: lastMonth, categoryId: food.id)
        let refund = Txn(bookId: bookId, type: .income, amountMinor: 2_000, accountId: accountId, categoryId: food.id)
        refund.refundOfTxnId = lastMonthExpense.id
        let thisExpense = Txn(bookId: bookId, type: .expense, amountMinor: 3_000, accountId: accountId, categoryId: traffic.id)

        let txns = [lastMonthExpense, refund, thisExpense]
        let summary = StatsEngine.summary(range: currentRange(), caliber: .cashFlow, txns: txns, claims: [])
        let breakdown = StatsEngine.breakdown(
            range: currentRange(),
            caliber: .cashFlow,
            txns: txns,
            claims: [],
            categories: [food, traffic]
        )

        XCTAssertEqual(summary.expenseMinor, 1_000)
        XCTAssertEqual(breakdown.slices.count, 1)
        XCTAssertEqual(breakdown.slices.first?.name, "交通")
        XCTAssertEqual(breakdown.slices.first?.amountMinor, 3_000)
        XCTAssertEqual(breakdown.refundOffsetMinor, -2_000)
        XCTAssertEqual(breakdown.sliceTotalMinor + breakdown.refundOffsetMinor, summary.expenseMinor)
    }

    /// 垫付口径：退款要同时冲减「垫付」和「待报销」，两者不能互相矛盾
    func testAdvanceCaliberNetsRefund() {
        let claim = makeDraftClaim()
        let original = Txn(bookId: bookId, type: .expense, amountMinor: 5_000, accountId: accountId)
        original.isReimbursable = true
        original.claimId = claim.id
        let refund = Txn(bookId: bookId, type: .income, amountMinor: 2_000, accountId: accountId)
        refund.refundOfTxnId = original.id

        let advance = StatsEngine.summary(
            range: currentRange(),
            caliber: .advance,
            txns: [original, refund],
            claims: [claim]
        )
        XCTAssertEqual(advance.expenseMinor, 3_000)
        XCTAssertEqual(advance.pendingMinor, 3_000)
        XCTAssertEqual(advance.expenseMinor, advance.pendingMinor)
    }

    /// 退款冲减「原支出」的分类，而不是退款流水自己的分类
    func testRefundUsesOriginalCategory() {        let food = Category(bookId: bookId, name: "餐饮", kind: .expense)
        let traffic = Category(bookId: bookId, name: "交通", kind: .expense)
        let original = Txn(bookId: bookId, type: .expense, amountMinor: 5_000, accountId: accountId, categoryId: food.id)
        let refund = Txn(bookId: bookId, type: .income, amountMinor: 2_000, accountId: accountId, categoryId: traffic.id)
        refund.refundOfTxnId = original.id

        let breakdown = StatsEngine.breakdown(
            range: currentRange(),
            caliber: .cashFlow,
            txns: [original, refund],
            claims: [],
            categories: [food, traffic]
        )
        XCTAssertEqual(breakdown.slices.count, 1)
        XCTAssertEqual(breakdown.slices.first?.name, "餐饮")
        XCTAssertEqual(breakdown.slices.first?.amountMinor, 3_000)
        XCTAssertEqual(breakdown.refundOffsetMinor, 0)
    }
}
