import XCTest
import Foundation
@testable import Ledger

final class CashFlowForecastTests: XCTestCase {
    private let bookId = UUID()
    private var calendar: Calendar { AppCalendar.gregorian }

    /// 固定参考日（2026-03-15），保证测试不随系统日期漂移
    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)) ?? Date()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? reference
    }

    private func makeAccount(
        _ type: AccountType,
        opening: Int64,
        include: Bool = true,
        archived: Bool = false
    ) -> Account {
        let account = Account(bookId: bookId, name: type.displayName, type: type, openingBalanceMinor: opening)
        account.includeInNetWorth = include
        account.isArchived = archived
        return account
    }

    private func makeLoan() -> Loan {
        Loan(
            bookId: bookId,
            name: "房贷",
            type: .mortgageCommercial,
            principalMinor: 1_000_000,
            annualRateBp: 0,
            termMonths: 12,
            startDate: date(2026, 1, 1),
            firstDueDate: date(2026, 2, 17),
            dueDay: 17,
            repaymentMethod: .equalInstallment,
            paymentAccountId: UUID()
        )
    }

    private func plan(
        days: Int = 30,
        accounts: [Account] = [],
        transactions: [Txn] = [],
        loans: [Loan] = [],
        items: [LoanScheduleItem] = [],
        rules: [RecurringRule] = [],
        debts: [Debt] = [],
        statements: [Statement] = []
    ) -> CashFlowPlan {
        CashFlowForecast.plan(
            from: reference,
            days: days,
            accounts: accounts,
            transactions: transactions,
            loans: loans,
            loanScheduleItems: items,
            recurringRules: rules,
            debts: debts,
            statements: statements
        )
    }

    func testStartingBalanceOnlyLiquidAccounts() {
        let cash = makeAccount(.cash, opening: 100_000)
        let credit = makeAccount(.credit, opening: -50_000)
        let archived = makeAccount(.debit, opening: 20_000, archived: true)
        let excluded = makeAccount(.debit, opening: 30_000, include: false)
        let provident = makeAccount(.providentFund, opening: 40_000)

        let plan = plan(accounts: [cash, credit, archived, excluded, provident])
        XCTAssertEqual(plan.startingBalanceMinor, 100_000)
        XCTAssertTrue(plan.events.isEmpty)
    }

    func testLoanRepaymentEventsInsideWindow() {
        let loan = makeLoan()
        let inside = LoanScheduleItem(
            loanId: loan.id,
            periodIndex: 3,
            dueDate: date(2026, 3, 17),
            principalMinor: 40_000,
            interestMinor: 10_000,
            feeMinor: 0
        )
        let outside = LoanScheduleItem(
            loanId: loan.id,
            periodIndex: 4,
            dueDate: date(2026, 4, 17),
            principalMinor: 40_000,
            interestMinor: 10_000,
            feeMinor: 0
        )

        let plan = plan(loans: [loan], items: [inside, outside])
        XCTAssertEqual(plan.events.count, 1)
        XCTAssertEqual(plan.events.first?.kind, CashFlowKind.loan)
        XCTAssertEqual(plan.events.first?.amountMinor, -50_000)
        XCTAssertTrue(plan.events.first?.title.contains("房贷") == true)
        XCTAssertEqual(plan.outflowMinor, 50_000)
    }

    func testRecurringExpenseAndIncomeProjected() {
        let expense = RecurringRule(
            bookId: bookId,
            title: "房租",
            templateType: .expense,
            amountMinor: 200_000,
            accountId: UUID(),
            frequency: .monthly,
            startDate: date(2026, 3, 20)
        )
        let income = RecurringRule(
            bookId: bookId,
            title: "工资",
            templateType: .income,
            amountMinor: 300_000,
            accountId: UUID(),
            frequency: .monthly,
            startDate: date(2026, 3, 18)
        )

        let plan = plan(rules: [expense, income])
        XCTAssertEqual(plan.events.count, 2)
        XCTAssertEqual(plan.inflowMinor, 300_000)
        XCTAssertEqual(plan.outflowMinor, 200_000)
        XCTAssertEqual(plan.netMinor, 100_000)
        // 第二次房租（4/20）在 30 天窗口外
        XCTAssertEqual(plan.events.filter { $0.kind == .recurring }.count, 2)
    }

    func testRegisteredStatementOverridesEstimate() {
        let card = makeAccount(.credit, opening: 0)
        card.billDay = 10
        card.dueDay = 20
        let statement = Statement(
            accountId: card.id,
            periodMonth: "2026-02",
            billAmountMinor: 100_000,
            minimumPaymentMinor: 10_000,
            dueDate: date(2026, 3, 20)
        )
        statement.paidAmountMinor = 30_000

        let plan = plan(accounts: [card], statements: [statement])
        let cardEvents = plan.events.filter { $0.kind == .creditCard }
        XCTAssertEqual(cardEvents.count, 1)
        XCTAssertEqual(cardEvents.first?.amountMinor, -70_000)
        XCTAssertTrue(cardEvents.first?.title.contains(card.displayName) == true)
    }

    func testCreditCardEstimateFromStatementPeriod() {
        let card = makeAccount(.credit, opening: 0)
        card.billDay = 10
        card.dueDay = 20
        let expense = Txn(
            bookId: bookId,
            type: .expense,
            amountMinor: 60_000,
            accountId: card.id,
            occurredAt: date(2026, 2, 20)
        )

        let plan = plan(accounts: [card], transactions: [expense])
        let cardEvents = plan.events.filter { $0.kind == .creditCard }
        XCTAssertEqual(cardEvents.count, 1)
        XCTAssertEqual(cardEvents.first?.amountMinor, -60_000)
        XCTAssertTrue(cardEvents.first?.title.contains("估算") == true)
    }

    func testDebtReceivableAndPayable() {
        let lend = Debt(bookId: bookId, direction: .lend, counterparty: "张三", amountMinor: 50_000, dueDate: date(2026, 3, 18))
        let borrow = Debt(bookId: bookId, direction: .borrow, counterparty: "李四", amountMinor: 30_000, dueDate: date(2026, 3, 19))

        let plan = plan(debts: [lend, borrow])
        XCTAssertEqual(plan.events.count, 2)
        XCTAssertEqual(plan.inflowMinor, 50_000)
        XCTAssertEqual(plan.outflowMinor, 30_000)
        XCTAssertTrue(plan.events.contains { $0.kind == .receivable && $0.amountMinor == 50_000 })
        XCTAssertTrue(plan.events.contains { $0.kind == .payable && $0.amountMinor == -30_000 })
    }

    func testTotalsAndEndingBalance() {
        let cash = makeAccount(.cash, opening: 100_000)
        let loan = makeLoan()
        let item = LoanScheduleItem(
            loanId: loan.id,
            periodIndex: 3,
            dueDate: date(2026, 3, 17),
            principalMinor: 50_000,
            interestMinor: 0,
            feeMinor: 0
        )
        let income = RecurringRule(
            bookId: bookId,
            title: "工资",
            templateType: .income,
            amountMinor: 30_000,
            accountId: UUID(),
            frequency: .monthly,
            startDate: date(2026, 3, 18)
        )
        let borrow = Debt(bookId: bookId, direction: .borrow, counterparty: "李四", amountMinor: 20_000, dueDate: date(2026, 3, 19))

        let plan = plan(
            accounts: [cash],
            loans: [loan],
            items: [item],
            rules: [income],
            debts: [borrow]
        )
        XCTAssertEqual(plan.startingBalanceMinor, 100_000)
        XCTAssertEqual(plan.outflowMinor, 70_000)
        XCTAssertEqual(plan.inflowMinor, 30_000)
        XCTAssertEqual(plan.netMinor, -40_000)
        XCTAssertEqual(plan.endingBalanceMinor, 60_000)
    }

    func testWindowBoundaryExcludesEndDay() {
        // 30 天窗口：3/15 起，3/15 + 30 = 4/14 00:00 结束，4/14 当天不计入
        let onEnd = Debt(bookId: bookId, direction: .lend, counterparty: "甲", amountMinor: 10_000, dueDate: date(2026, 4, 14))
        let inside = Debt(bookId: bookId, direction: .lend, counterparty: "乙", amountMinor: 20_000, dueDate: date(2026, 4, 13))

        let plan = plan(debts: [onEnd, inside])
        XCTAssertEqual(plan.events.count, 1)
        XCTAssertEqual(plan.events.first?.amountMinor, 20_000)
    }
}
