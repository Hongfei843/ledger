import XCTest
@testable import Ledger

final class CookieCSVImporterTests: XCTestCase {
    private func metaBase64(id: String, emoji: String, reimbursable: Bool = false) -> String {
        let json = #"{"id":"\#(id)","firstTypeEmoji":"\#(emoji)","needReimbursement":\#(reimbursable)}"#
        return Data(json.utf8).base64EncodedString()
    }

    private func sampleCSV() -> String {
        let m1 = metaBase64(id: "AAA-111", emoji: "u1f958")
        let m2 = metaBase64(id: "BBB-222", emoji: "u1f4b0")
        return """
        Cookie账单(全部)
        时间,收支,一级分类,二级分类,金额,币种,备注,卡包,账本,标签,其他
        2026-11-23 21:37:08,支出,餐饮,,¥38,CNY,"水煮,油炸",,,,\(m1)
        2026-11-18 14:57:20,收入,工资,,¥769.23,CNY,金科力,,,,\(m2)
        """
    }

    func testParseBasicRows() throws {
        let records = try CookieCSVImporter.parse(text: sampleCSV())
        XCTAssertEqual(records.count, 2)

        let first = records[0]
        XCTAssertEqual(first.externalId, "AAA-111")
        XCTAssertFalse(first.isIncome)
        XCTAssertEqual(first.amountMinor, 3800)
        XCTAssertEqual(first.primaryCategory, "餐饮")
        XCTAssertEqual(first.note, "水煮,油炸", "带引号的字段应保留内部逗号")
        XCTAssertEqual(first.emoji, String(Character(UnicodeScalar(0x1F958)!)))

        let second = records[1]
        XCTAssertTrue(second.isIncome)
        XCTAssertEqual(second.amountMinor, 76923)
    }

    func testParseSkipsTitleAndHeader() throws {
        let records = try CookieCSVImporter.parse(text: sampleCSV())
        XCTAssertFalse(records.contains { $0.primaryCategory == "一级分类" })
    }

    func testAmountFormats() throws {
        let m = metaBase64(id: "X", emoji: "u1f4f1")
        let csv = """
        时间,收支,一级分类,二级分类,金额,币种,备注,卡包,账本,标签,其他
        2026-11-24 10:40:22,支出,App 订阅,,¥10,CNY,DSH,,,,\(m)
        2026-11-11 15:30:22,支出,电费,,¥30,CNY,,,,,\(m)
        """
        let records = try CookieCSVImporter.parse(text: csv)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].amountMinor, 1000)
        XCTAssertEqual(records[1].amountMinor, 3000)
    }

    func testAccountNameColumn() throws {
        let m = metaBase64(id: "Y", emoji: "u1f4b3")
        let csv = """
        时间,收支,一级分类,二级分类,金额,币种,备注,卡包,账本,标签,其他
        2026-11-10 15:32:53,支出,餐饮,,¥2,CNY,,中信银行信用卡,,,\(m)
        """
        let records = try CookieCSVImporter.parse(text: csv)
        XCTAssertEqual(records.first?.accountName, "中信银行信用卡")
        XCTAssertEqual(ImportService.inferAccountType(from: "中信银行信用卡"), .credit)
        XCTAssertEqual(ImportService.inferAccountType(from: "蚂蚁花呗"), .bnpl)
    }

    func testInvalidFileThrows() {
        XCTAssertThrowsError(try CookieCSVImporter.parse(text: "随便什么内容"))
    }

    func testSplitFieldsWithQuotes() {
        let fields = CookieCSVImporter.splitFields("a,\"b,c\",d")
        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(fields[1], "b,c")
    }

    func testParseQuotedMultilineNoteAndCRLF() throws {
        let meta = metaBase64(id: "MULTILINE", emoji: "u1f35c")
        let csv = "时间,收支,一级分类,二级分类,金额,币种,备注,卡包,账本,标签,其他\r\n"
            + "2026-11-24 10:40:22,支出,餐饮,,¥12.30,CNY,\"第一行\r\n第二行,含逗号\",,,,\(meta)\r\n"

        let records = try CookieCSVImporter.parse(text: csv)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.note, "第一行\r\n第二行,含逗号")
        XCTAssertEqual(records.first?.externalId, "MULTILINE")
    }

    func testTransferRowsAreNotMisclassifiedAsExpense() throws {
        let expenseMeta = metaBase64(id: "EXPENSE", emoji: "u1f35c")
        let transferMeta = metaBase64(id: "TRANSFER", emoji: "u1f4b3")
        let csv = """
        时间,收支,一级分类,二级分类,金额,币种,备注,卡包,账本,标签,其他
        2026-11-24 10:40:22,支出,餐饮,,¥12.30,CNY,午饭,,,,\(expenseMeta)
        2026-11-24 11:40:22,转账,转账,,¥100,CNY,银行卡互转,,,,\(transferMeta)
        """
        let records = try CookieCSVImporter.parse(text: csv)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.externalId, "EXPENSE")
    }
}
