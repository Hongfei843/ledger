import XCTest
import Foundation
@testable import Ledger

final class BillCSVTests: XCTestCase {
    private let bookId = UUID()
    private let accountId = UUID()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return AppCalendar.gregorian.date(from: comps)!
    }

    private func alipayCSV() -> String {
        """
        支付宝交易记录明细查询
        账号:test@example.com
        起始日期:[2026-11-01 00:00:00]    终止日期:[2026-11-30 23:59:59]
        ---------------------------------
        交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注
        2026-11-23 21:37:08,餐饮美食,水煮店,水煮油炸,支出,38.00,余额宝,交易成功,20261123001,M001,
        2026-11-22 10:00:00,转账,张三,转账,不计收支,100.00,余额宝,交易成功,20261122002,M002,
        2026-11-21 09:00:00,退款,某商城,退款,收入,20.00,余额宝,退款成功,20261121003,M003,
        2026-11-20 18:00:00,工资,公司,工资,收入,7690.00,银行卡,交易成功,20261120004,M004,
        """
    }

    func testParseAlipaySkippingPreambleAndNoise() throws {
        let result = try BillCSVParser.parse(text: alipayCSV())
        // 「不计收支」与「退款成功」被跳过，剩 2 条
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.source, .alipay)
        XCTAssertEqual(result.skipped, 2)

        let first = result.rows[0]
        XCTAssertEqual(first.amountMinor, 3800)
        XCTAssertFalse(first.isIncome)
        XCTAssertEqual(first.counterparty, "水煮店")
        XCTAssertEqual(first.externalId, "20261123001")

        XCTAssertTrue(result.rows[1].isIncome)
        XCTAssertEqual(result.rows[1].amountMinor, 769000)
    }

    func testMatcherFindsMissing() {
        let rows = [
            BillRow(occurredAt: date(2026, 11, 23), amountMinor: 3800, isIncome: false, counterparty: "A", subject: nil, externalId: "1", rawLine: ""),
            BillRow(occurredAt: date(2026, 11, 22), amountMinor: 1200, isIncome: false, counterparty: "B", subject: nil, externalId: "2", rawLine: ""),
            BillRow(occurredAt: date(2026, 11, 21), amountMinor: 500, isIncome: false, counterparty: "C", subject: nil, externalId: "3", rawLine: "")
        ]

        let existing = [
            Txn(bookId: bookId, type: .expense, amountMinor: 3800, accountId: accountId, occurredAt: date(2026, 11, 23)),
            Txn(bookId: bookId, type: .expense, amountMinor: 1200, accountId: accountId, occurredAt: date(2026, 11, 21))
        ]

        let result = BillMatcher.compare(rows: rows, transactions: existing)
        XCTAssertEqual(result.matchedCount, 2)
        XCTAssertEqual(result.missing.count, 1)
        XCTAssertEqual(result.missing.first?.externalId, "3")
        // 1200 那条日期差 1 天，应被容忍
        XCTAssertTrue(result.missing.allSatisfy { $0.externalId != "2" })
    }

    func testMatcherDirectionMatters() {
        let rows = [
            BillRow(occurredAt: date(2026, 11, 23), amountMinor: 1000, isIncome: true, counterparty: nil, subject: nil, externalId: "x", rawLine: "")
        ]
        let existing = [
            Txn(bookId: bookId, type: .expense, amountMinor: 1000, accountId: accountId, occurredAt: date(2026, 11, 23))
        ]
        let result = BillMatcher.compare(rows: rows, transactions: existing)
        XCTAssertEqual(result.matchedCount, 0, "支出不能匹配收入")
        XCTAssertEqual(result.missing.count, 1)
    }

    func testMatcherDetectsExtra() {
        let rows = [
            BillRow(occurredAt: date(2026, 11, 23), amountMinor: 3800, isIncome: false, counterparty: nil, subject: nil, externalId: "1", rawLine: "")
        ]
        let existing = [
            Txn(bookId: bookId, type: .expense, amountMinor: 3800, accountId: accountId, occurredAt: date(2026, 11, 23)),
            Txn(bookId: bookId, type: .expense, amountMinor: 999, accountId: accountId, occurredAt: date(2026, 11, 22))
        ]
        let result = BillMatcher.compare(rows: rows, transactions: existing)
        XCTAssertEqual(result.extra.count, 1)
        XCTAssertEqual(result.extra.first?.amountMinor, 999)
    }

    func testCSVFieldWithQuotes() {
        let fields = BillCSVParser.splitFields("a,\"b,c\",d")
        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(fields[1], "b,c")
    }
}
