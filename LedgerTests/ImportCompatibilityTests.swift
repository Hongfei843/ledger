import XCTest
import SwiftData
@testable import Ledger

final class ImportCompatibilityTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    @MainActor
    private func makeV2BackupJSON() throws -> Data {
        let container = ModelContainerFactory.preview()
        self.container = container
        let context = container.mainContext

        let book = Book(name: "日常")
        context.insert(book)
        let account = Account(bookId: book.id, name: "储蓄卡", type: .debit, openingBalanceMinor: 100_000)
        account.cachedBalanceMinor = 98_000
        context.insert(account)
        let category = Category(bookId: book.id, name: "餐饮", kind: .expense)
        context.insert(category)
        let txn = Txn(
            bookId: book.id,
            type: .expense,
            amountMinor: 2_000,
            accountId: account.id,
            occurredAt: Date(),
            categoryId: category.id,
            payee: "面馆"
        )
        context.insert(txn)
        try context.save()

        let backup = try BackupService.makeBackup(context: context)
        return try BackupService.encode(backup)
    }

    @MainActor
    func testTolerantDecodeMissingNewFields() throws {
        let data = try makeV2BackupJSON()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var accounts = try XCTUnwrap(object["accounts"] as? [[String: Any]])
        accounts[0].removeValue(forKey: "cachedBalanceMinor")
        accounts[0].removeValue(forKey: "positionCostMinor")
        object["accounts"] = accounts
        let trimmed = try JSONSerialization.data(withJSONObject: object)

        let result = try BackupService.decodeDetailed(trimmed)
        XCTAssertEqual(result.version, 2)
        XCTAssertFalse(result.isLegacy)
        XCTAssertEqual(result.backup.accounts.first?.cachedBalanceMinor, 0)
        XCTAssertNil(result.backup.accounts.first?.positionCostMinor)
        XCTAssertEqual(result.backup.txns.first?.payee, "面馆")
    }

    func testAcceptOlderFormatVersion() throws {
        var object = [
            "formatVersion": 1,
            "exportedAt": "2026-01-01T00:00:00Z",
            "books": [],
            "accounts": [],
            "categories": [],
            "txns": [],
            "claims": [],
            "loans": [],
            "scheduleItems": [],
            "statements": [],
            "reconciliationRuns": [],
            "debts": [],
            "merchantRules": [],
            "captureRecords": [],
            "recurringRules": [],
            "quickTemplates": []
        ] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: object)
        let result = try BackupService.decodeDetailed(data)
        XCTAssertEqual(result.version, 1)
        XCTAssertFalse(result.isLegacy)
        object["formatVersion"] = 99
        let newer = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try BackupService.decodeDetailed(newer)) { error in
            guard case BackupError.unsupportedVersion(99) = error else {
                return XCTFail("应拒绝更新的格式版本，实际：\(error)")
            }
        }
    }

    func testLegacyV1BackupImport() throws {
        let legacy = """
        {
          "schemaVersion": 1,
          "exportedAt": "2026-02-01T08:00:00Z",
          "accounts": [
            {"id": "11111111-1111-1111-1111-111111111111", "name": "招行卡", "type": "debit", "openingBalanceMinor": 50000, "cachedBalanceMinor": 40000, "includeInNetWorth": true, "isArchived": false}
          ],
          "categories": [
            {"id": "22222222-2222-2222-2222-222222222222", "name": "餐饮", "kind": "expense", "iconEmoji": "🍜"}
          ],
          "transactions": [
            {"id": "33333333-3333-3333-3333-333333333333", "type": "expense", "amountMinor": 10000, "accountId": "11111111-1111-1111-1111-111111111111", "categoryId": "22222222-2222-2222-2222-222222222222", "occurredAt": "2026-01-15T12:00:00Z", "note": "午饭", "isReimbursable": false, "refundOfTxnId": "", "source": "manual"}
          ]
        }
        """
        let result = try BackupService.decodeDetailed(Data(legacy.utf8))
        XCTAssertTrue(result.isLegacy)
        XCTAssertEqual(result.version, 1)
        XCTAssertEqual(result.backup.accounts.count, 1)
        XCTAssertEqual(result.backup.categories.count, 1)
        XCTAssertEqual(result.backup.txns.count, 1)
        XCTAssertEqual(result.backup.txns.first?.amountMinor, 10_000)
        XCTAssertEqual(result.backup.txns.first?.note, "午饭")
        XCTAssertEqual(result.backup.books.count, 1)
    }

    func testImportTextDecoderHandlesBOMAndGB18030() throws {
        let text = "交易时间,金额\n2026-03-05 12:00:00,35.00"
        let utf8 = Data(text.utf8)
        XCTAssertEqual(ImportTextDecoder.decode(utf8), text)

        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(utf8)
        XCTAssertEqual(ImportTextDecoder.decode(bom), text)

        let gb = try XCTUnwrap(text.data(using: String.Encoding(rawValue: 0x80000632)))
        XCTAssertEqual(ImportTextDecoder.decode(gb), text)
    }

    func testBillCSVFullWidthHeadersAndSemicolon() throws {
        let csv = """
        交易时间（北京时间）;金额（元）;收/支;交易对方;商品说明;交易状态
        2026-03-05 12:00:00;35.00;支出;星巴克;咖啡;交易成功
        2026-03-06 09:30:00;120.00;收入;公司;报销;交易成功
        """
        let result = try BillCSVParser.parse(text: csv)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].amountMinor, 3_500)
        XCTAssertEqual(result.rows[0].counterparty, "星巴克")
        XCTAssertFalse(result.rows[0].isIncome)
        XCTAssertTrue(result.rows[1].isIncome)
    }

    @MainActor
    func testCookieImportDoesNotReuseOtherBookReferences() throws {
        let container = ModelContainerFactory.preview()
        self.container = container
        let context = container.mainContext
        let otherBook = Book(name: "其他账本")
        let currentBook = Book(name: "当前账本")
        context.insert(otherBook)
        context.insert(currentBook)
        let otherAccount = Account(bookId: otherBook.id, name: "招商", type: .debit)
        let otherCategory = Category(bookId: otherBook.id, name: "餐饮", kind: .expense)
        let fallback = Account(bookId: currentBook.id, name: "现金", type: .cash)
        context.insert(otherAccount)
        context.insert(otherCategory)
        context.insert(fallback)
        try context.save()

        let record = CookieRecord(
            externalId: nil,
            occurredAt: Date(),
            isIncome: false,
            primaryCategory: "餐饮",
            secondaryCategory: nil,
            amountMinor: 1_200,
            note: "午饭",
            accountName: "招商",
            bookName: nil,
            tags: [],
            emoji: nil,
            needReimbursement: false
        )
        _ = ImportService.importCookie(
            records: [record],
            defaultAccountId: fallback.id,
            bookId: currentBook.id,
            context: context
        )

        let txn = try XCTUnwrap(context.fetch(FetchDescriptor<Txn>()).first)
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<Account>()).first { $0.id == txn.accountId })
        let category = try XCTUnwrap(context.fetch(FetchDescriptor<Ledger.Category>()).first { $0.id == txn.categoryId })
        XCTAssertEqual(txn.bookId, currentBook.id)
        XCTAssertEqual(account.bookId, currentBook.id)
        XCTAssertEqual(category.bookId, currentBook.id)
        XCTAssertNotEqual(account.id, otherAccount.id)
        XCTAssertNotEqual(category.id, otherCategory.id)
    }
}
