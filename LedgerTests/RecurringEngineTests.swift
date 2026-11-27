import XCTest
import Foundation
import SwiftData
@testable import Ledger

final class RecurringEngineTests: XCTestCase {
    private let calendar = AppCalendar.gregorian

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return calendar.date(from: comps)!
    }

    private func makeRule(
        start: Date,
        frequency: RecurrenceFrequency = .monthly,
        interval: Int = 1,
        autoCreate: Bool = true
    ) -> RecurringRule {
        let rule = RecurringRule(
            bookId: UUID(),
            title: "房租",
            templateType: .expense,
            amountMinor: 300_000,
            accountId: UUID(),
            frequency: frequency,
            startDate: start
        )
        rule.interval = interval
        rule.autoCreate = autoCreate
        return rule
    }

    /// 每月 31 号起，2 月应被收敛到月末
    func testMonthlyClampsToMonthEnd() {
        let rule = makeRule(start: date(2026, 1, 31))
        guard let next = RecurringEngine.nextDate(after: rule.nextDate, frequency: .monthly, interval: 1) else {
            return XCTFail("应能算出下一天")
        }
        let comps = calendar.dateComponents([.month, .day], from: next)
        XCTAssertEqual(comps.month, 2)
        XCTAssertEqual(comps.day, 28)
    }

    /// 每天：从 3 天前到今天，应生成 4 条
    func testDailyDueDates() {
        let rule = makeRule(start: date(2026, 11, 21), frequency: .daily)
        let dates = RecurringEngine.dueDates(rule: rule, upTo: date(2026, 11, 24))
        XCTAssertEqual(dates.count, 4)
    }

    /// 已暂停的规则不生成
    func testPausedRuleProducesNothing() {
        let rule = makeRule(start: date(2026, 11, 1))
        rule.isPaused = true
        XCTAssertTrue(RecurringEngine.dueDates(rule: rule, upTo: date(2026, 11, 24)).isEmpty)
    }

    /// 未来的规则不提前生成
    func testFutureRuleProducesNothing() {
        let rule = makeRule(start: date(2026, 12, 1))
        XCTAssertTrue(RecurringEngine.dueDates(rule: rule, upTo: date(2026, 11, 24)).isEmpty)
    }

    /// 间隔 2 周
    func testBiweekly() {
        let rule = makeRule(start: date(2026, 11, 1), frequency: .weekly, interval: 2)
        guard let next = RecurringEngine.nextDate(after: rule.nextDate, frequency: .weekly, interval: 2) else {
            return XCTFail("应能算出下一天")
        }
        let days = calendar.dateComponents([.day], from: rule.nextDate, to: next).day
        XCTAssertEqual(days, 14)
    }

    /// 长时间未打开时不应无限生成
    func testLimit() {
        let rule = makeRule(start: date(2025, 1, 1), frequency: .daily)
        let dates = RecurringEngine.dueDates(rule: rule, upTo: date(2026, 11, 24), limit: 40)
        XCTAssertEqual(dates.count, 40)
    }

    @MainActor
    func testRecurringServiceRejectsCrossBookCategory() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let book = Book(name: "当前")
        let otherBook = Book(name: "其他")
        let account = Account(bookId: book.id, name: "现金", type: .cash)
        let otherCategory = Category(bookId: otherBook.id, name: "房租", kind: .expense)
        let today = date(2026, 11, 24)
        let rule = RecurringRule(
            bookId: book.id,
            title: "房租",
            templateType: .expense,
            amountMinor: 300_000,
            accountId: account.id,
            frequency: .monthly,
            startDate: today
        )
        rule.autoCreate = true
        rule.categoryId = otherCategory.id
        context.insert(book)
        context.insert(otherBook)
        context.insert(account)
        context.insert(otherCategory)
        context.insert(rule)
        try context.save()

        let result = RecurringService.run(context: context, today: today)
        XCTAssertEqual(result.createdCount, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Txn>()).isEmpty)
    }

    @MainActor
    func testRecurringServiceCreatesWithSameBookReferences() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let book = Book(name: "当前")
        let account = Account(bookId: book.id, name: "现金", type: .cash)
        let category = Category(bookId: book.id, name: "房租", kind: .expense)
        let today = date(2026, 11, 24)
        let rule = RecurringRule(
            bookId: book.id,
            title: "房租",
            templateType: .expense,
            amountMinor: 300_000,
            accountId: account.id,
            frequency: .monthly,
            startDate: today
        )
        rule.autoCreate = true
        rule.categoryId = category.id
        context.insert(book)
        context.insert(account)
        context.insert(category)
        context.insert(rule)
        try context.save()

        let result = RecurringService.run(context: context, today: today)
        XCTAssertEqual(result.createdCount, 1)
        let txn = try XCTUnwrap(context.fetch(FetchDescriptor<Txn>()).first)
        XCTAssertEqual(txn.bookId, book.id)
        XCTAssertEqual(txn.accountId, account.id)
        XCTAssertEqual(txn.categoryId, category.id)
        XCTAssertEqual(account.cachedBalanceMinor, -300_000)
    }
}
