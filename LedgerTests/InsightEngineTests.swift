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

    /// 没有数据时不应产出任何洞察（避免空话）
    func testNoDataNoInsight() {
        let insights = InsightEngine.generate(monthAnchor: Date(), txns: [], categories: [], claims: [])
        XCTAssertTrue(insights.isEmpty)
    }
}
