import XCTest
import Foundation
@testable import Ledger

final class MonthlyReportTests: XCTestCase {
    private let calendar = AppCalendar.gregorian

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeCategory(_ name: String) -> Ledger.Category {
        Ledger.Category(bookId: UUID(), name: name, kind: .expense)
    }

    private func makeTxn(
        type: TxnType,
        amount: Int64,
        day: Date,
        categoryId: UUID? = nil,
        payee: String? = nil,
        refundOf: UUID? = nil
    ) -> Txn {
        let txn = Txn(
            bookId: UUID(),
            type: type,
            amountMinor: amount,
            accountId: UUID(),
            occurredAt: day,
            categoryId: categoryId,
            payee: payee
        )
        txn.refundOfTxnId = refundOf
        return txn
    }

    func testTotalsAreNetOfRefunds() {
        let food = makeCategory("餐饮")
        let month = date(2026, 3, 15)
        let expense = makeTxn(type: .expense, amount: 10_000, day: on(5), categoryId: food.id)
        let refund = makeTxn(type: .income, amount: 2_000, day: on(6), refundOf: expense.id)
        let salary = makeTxn(type: .income, amount: 50_000, day: on(10))

        let report = MonthlyReportBuilder.build(
            monthAnchor: month,
            txns: [expense, refund, salary],
            categories: [food]
        )
        XCTAssertEqual(report.expenseMinor, 8_000)
        XCTAssertEqual(report.incomeMinor, 50_000)
        XCTAssertEqual(report.netMinor, 42_000)
        XCTAssertEqual(report.savingsRatePercent, 84)
        XCTAssertEqual(report.days.reduce(Int64(0)) { $0 + $1.expenseMinor }, 8_000)
    }

    func testCategoryRankingAndShare() {
        let food = makeCategory("餐饮")
        let traffic = makeCategory("交通")
        let month = date(2026, 3, 15)
        let txns = [
            makeTxn(type: .expense, amount: 6_000, day: on(3), categoryId: food.id),
            makeTxn(type: .expense, amount: 2_000, day: on(4), categoryId: traffic.id),
            makeTxn(type: .expense, amount: 2_000, day: on(5), categoryId: traffic.id)
        ]

        let report = MonthlyReportBuilder.build(monthAnchor: month, txns: txns, categories: [food, traffic])
        XCTAssertEqual(report.categories.count, 2)
        XCTAssertEqual(report.categories[0].name, "餐饮")
        XCTAssertEqual(report.categories[0].amountMinor, 6_000)
        XCTAssertEqual(report.categories[0].share, 0.6, accuracy: 0.0001)
        XCTAssertEqual(report.categories[1].amountMinor, 4_000)
    }

    func testPreviousMonthChange() {
        let month = date(2026, 3, 15)
        let previous = date(2026, 2, 10)
        let txns = [
            makeTxn(type: .expense, amount: 10_000, day: previous),
            makeTxn(type: .expense, amount: 12_000, day: on(10))
        ]

        let report = MonthlyReportBuilder.build(monthAnchor: month, txns: txns, categories: [])
        XCTAssertEqual(report.previousExpenseMinor, 10_000)
        XCTAssertEqual(report.expenseChangePercent, 20)
    }

    func testTopExpensesSorted() {
        let month = date(2026, 3, 15)
        let txns = [
            makeTxn(type: .expense, amount: 3_000, day: on(1), payee: "小"),
            makeTxn(type: .expense, amount: 20_000, day: on(2), payee: "大"),
            makeTxn(type: .expense, amount: 8_000, day: on(3), payee: "中")
        ]

        let report = MonthlyReportBuilder.build(monthAnchor: month, txns: txns, categories: [])
        XCTAssertEqual(report.topExpenses.map { $0.payee }, ["大", "中", "小"])
    }

    func testEmptyMonth() {
        let report = MonthlyReportBuilder.build(monthAnchor: date(2026, 4, 1), txns: [], categories: [])
        XCTAssertFalse(report.hasData)
        XCTAssertEqual(report.expenseChangePercent, nil)
        XCTAssertEqual(report.savingsRatePercent, nil)
        XCTAssertEqual(report.days.count, 30)
    }

    /// 跨月退款：分类合计 + 差额必须等于本月支出
    func testCrossMonthRefundKeepsCategorySumConsistent() {
        let food = makeCategory("餐饮")
        let traffic = makeCategory("交通")
        let month = date(2026, 3, 15)
        let lastMonthExpense = makeTxn(type: .expense, amount: 5_000, day: date(2026, 2, 10), categoryId: food.id)
        let refund = makeTxn(type: .income, amount: 2_000, day: on(6), categoryId: food.id, refundOf: lastMonthExpense.id)
        let thisExpense = makeTxn(type: .expense, amount: 3_000, day: on(7), categoryId: traffic.id)

        let report = MonthlyReportBuilder.build(
            monthAnchor: month,
            txns: [lastMonthExpense, refund, thisExpense],
            categories: [food, traffic]
        )

        XCTAssertEqual(report.expenseMinor, 1_000)
        XCTAssertEqual(report.categories.map { $0.name }, ["交通"])
        XCTAssertEqual(report.categories.first?.amountMinor, 3_000)
        XCTAssertEqual(report.refundOffsetMinor, -2_000)
        XCTAssertEqual(report.categories.reduce(Int64(0)) { $0 + $1.amountMinor } + report.refundOffsetMinor, report.expenseMinor)
    }

    /// 上月只有收入、没有支出时，不能笼统写「上月无数据」
    func testPreviousHasDataWhenOnlyIncome() {
        let month = date(2026, 3, 15)
        let txns = [
            makeTxn(type: .income, amount: 10_000, day: date(2026, 2, 10)),
            makeTxn(type: .expense, amount: 3_000, day: on(2))
        ]

        let report = MonthlyReportBuilder.build(monthAnchor: month, txns: txns, categories: [])
        XCTAssertTrue(report.previousHasData)
        XCTAssertNil(report.expenseChangePercent)
        XCTAssertEqual(report.incomeChangePercent, -100)
    }

    private func on(_ day: Int) -> Date {
        date(2026, 3, day)
    }
}

final class InvestmentServiceTests: XCTestCase {
    private func makeInvestmentAccount(cost: Int64?) -> Account {
        let account = Account(bookId: UUID(), name: "基金", type: .investment, openingBalanceMinor: 100_000)
        account.positionCostMinor = cost
        return account
    }

    func testProfitAndRate() throws {
        let account = makeInvestmentAccount(cost: 80_000)
        let position = try XCTUnwrap(InvestmentService.position(for: account, txns: []))
        XCTAssertEqual(position.valueMinor, 100_000)
        XCTAssertEqual(position.profitMinor, 20_000)
        XCTAssertEqual(position.ratePercent ?? 0, 25, accuracy: 0.001)
    }

    func testMissingCostGivesNoRate() throws {
        let account = makeInvestmentAccount(cost: nil)
        let position = try XCTUnwrap(InvestmentService.position(for: account, txns: []))
        XCTAssertNil(position.profitMinor)
        XCTAssertNil(position.ratePercent)
    }

    func testOnlyInvestmentAccountsCounted() {
        let fund = makeInvestmentAccount(cost: 80_000)
        let cash = Account(bookId: UUID(), name: "现金", type: .cash)
        let portfolio = InvestmentService.portfolio(accounts: [fund, cash], txns: [])
        XCTAssertEqual(portfolio.positions.count, 1)
        XCTAssertEqual(portfolio.valueMinor, 100_000)
        XCTAssertEqual(portfolio.costMinor, 80_000)
        XCTAssertEqual(portfolio.profitMinor, 20_000)
    }

    func testLossRate() throws {
        let account = makeInvestmentAccount(cost: 120_000)
        let position = try XCTUnwrap(InvestmentService.position(for: account, txns: []))
        XCTAssertEqual(position.profitMinor, -20_000)
        XCTAssertEqual(position.ratePercent ?? 0, -16.6667, accuracy: 0.001)
    }
}
