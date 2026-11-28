import XCTest
import Foundation
@testable import Ledger

final class InsightEngineTests: XCTestCase {
    private let bookId = UUID()
    private let accountId = UUID()

    private func monthOffset(_ offset: Int) -> Date {
        AppCalendar.gregorian.date(byAdding: .month, value: offset, to: Date()) ?? Date()
    }

    /// 单笔远超该分类均值时，应给出一条异常提醒
    func testOutlierDetection() {
        let food = Category(bookId: bookId, name: "餐饮", kind: .expense)

        var txns: [Txn] = []
        // 近期 4 笔小额餐饮，均值约 25 元
        for index in 0..<4 {
            let txn = Txn(
                bookId: bookId,
                type: .expense,
                amountMinor: 2500,
                accountId: accountId,
                occurredAt: AppCalendar.gregorian.date(byAdding: .day, value: -index - 1, to: Date()) ?? Date(),
                categoryId: food.id
            )
            txns.append(txn)
        }
        // 本月一笔 300 元
        let big = Txn(
            bookId: bookId,
            type: .expense,
            amountMinor: 30000,
            accountId: accountId,
            occurredAt: Date(),
            categoryId: food.id
        )
        txns.append(big)

        let insights = InsightEngine.generate(
            monthAnchor: Date(),
            txns: txns,
            categories: [food],
            claims: []
        )
        XCTAssertTrue(insights.contains { $0.id.hasPrefix("outlier") }, "应识别出异常大额")
    }

    /// 同一备注连续三个月出现，应识别为疑似订阅
    func testSubscriptionDetection() {
        let other = Category(bookId: bookId, name: "订阅服务", kind: .expense)
        var txns: [Txn] = []
        for offset in 0...2 {
            let txn = Txn(
                bookId: bookId,
                type: .expense,
                amountMinor: 2500,
                accountId: accountId,
                occurredAt: monthOffset(-offset),
                categoryId: other.id,
                note: "某视频会员"
            )
            txns.append(txn)
        }

        let insights = InsightEngine.generate(
            monthAnchor: Date(),
            txns: txns,
            categories: [other],
            claims: []
        )
        XCTAssertTrue(insights.contains { $0.id.hasPrefix("subscription") })
    }

    /// 同一备注连续三个月出现，但金额波动大、频率高 → 不应判成订阅
    func testEverydayNoteIsNotSubscription() {
        let food = Category(bookId: bookId, name: "餐饮", kind: .expense)
        let amounts: [Int64] = [1_200, 3_800, 2_500]
        var txns: [Txn] = []
        for (offset, amount) in amounts.enumerated() {
            let txn = Txn(
                bookId: bookId,
                type: .expense,
                amountMinor: amount,
                accountId: accountId,
                occurredAt: monthOffset(-offset),
                categoryId: food.id,
                note: "午饭"
            )
            txns.append(txn)
        }

        let insights = InsightEngine.generate(
            monthAnchor: Date(),
            txns: txns,
            categories: [food],
            claims: []
        )
        XCTAssertFalse(insights.contains { $0.id.hasPrefix("subscription") })
    }

    /// 历史月份洞察只看该月及之前的数据，不把之后的流水带进来
    func testInsightUsesMonthAnchorAsWindowEnd() {
        let service = Category(bookId: bookId, name: "订阅服务", kind: .expense)
        let pastMonth = AppCalendar.gregorian.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let calendar = AppCalendar.gregorian

        var txns: [Txn] = []
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .month, value: offset, to: pastMonth) else { continue }
            txns.append(
                Txn(
                    bookId: bookId,
                    type: .expense,
                    amountMinor: 2_500,
                    accountId: accountId,
                    occurredAt: day,
                    categoryId: service.id,
                    note: "某会员"
                )
            )
        }

        let insights = InsightEngine.generate(
            monthAnchor: pastMonth,
            txns: txns,
            categories: [service],
            claims: []
        )
        // 回看 -6 月时，-5、-4 月还没发生，不构成「连续 3 个月订阅」
        XCTAssertFalse(insights.contains { $0.id.hasPrefix("subscription") })

        // 看最新一个月时，三个月都在范围内，才应识别
        let latest = InsightEngine.generate(
            monthAnchor: Date(),
            txns: txns,
            categories: [service],
            claims: []
        )
        XCTAssertTrue(latest.contains { $0.id.hasPrefix("subscription") })
    }

    /// 没有数据时不应产出任何洞察（避免空话）
    func testNoDataNoInsight() {
        let insights = InsightEngine.generate(monthAnchor: Date(), txns: [], categories: [], claims: [])
        XCTAssertTrue(insights.isEmpty)
    }
}
