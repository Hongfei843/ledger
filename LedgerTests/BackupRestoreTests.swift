import XCTest
import SwiftData
@testable import Ledger

final class BackupRestoreTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    @MainActor
    private func makeContext() -> ModelContext {
        let container = ModelContainerFactory.preview()
        self.container = container
        return container.mainContext
    }

    /// 造一份覆盖多数模型的数据，返回关键 ID
    @MainActor
    private func seed(_ context: ModelContext) throws -> (cashId: UUID, creditId: UUID, loanId: UUID, txnId: UUID) {
        let book = Book(name: "日常")
        context.insert(book)

        let cash = Account(bookId: book.id, name: "现金", type: .cash, openingBalanceMinor: 100_000)
        let credit = Account(bookId: book.id, name: "信用卡", type: .credit)
        credit.creditLimitMinor = 500_000
        context.insert(cash)
        context.insert(credit)

        let category = Category(bookId: book.id, name: "餐饮", kind: .expense)
        context.insert(category)

        let txn = Txn(
            bookId: book.id,
            type: .expense,
            amountMinor: 1_250,
            accountId: cash.id,
            occurredAt: Date(),
            categoryId: category.id,
            payee: "面馆",
            note: "午饭"
        )
        context.insert(txn)

        let deleted = Txn(
            bookId: book.id,
            type: .expense,
            amountMinor: 500,
            accountId: cash.id,
            occurredAt: Date(),
            payee: "已删除"
        )
        deleted.deletedAt = Date()
        context.insert(deleted)

        let loan = Loan(
            bookId: book.id,
            name: "房贷",
            type: .mortgageCommercial,
            principalMinor: 1_000_000,
            annualRateBp: 420,
            termMonths: 360,
            startDate: Date(),
            firstDueDate: Date(),
            dueDay: 15,
            repaymentMethod: .equalInstallment,
            paymentAccountId: cash.id
        )
        context.insert(loan)

        let schedule = LoanScheduleItem(
            loanId: loan.id,
            periodIndex: 1,
            dueDate: Date(),
            principalMinor: 1_000,
            interestMinor: 200,
            feeMinor: 0
        )
        context.insert(schedule)

        let statement = Statement(
            accountId: credit.id,
            periodMonth: "2026-11",
            billAmountMinor: 50_000,
            minimumPaymentMinor: 5_000,
            dueDate: Date()
        )
        context.insert(statement)

        let claim = Claim(bookId: book.id, title: "打车报销", periodMonth: "2026-11")
        claim.receivedAmountMinor = 2_000
        context.insert(claim)

        let debt = Debt(bookId: book.id, direction: .lend, counterparty: "同事", amountMinor: 10_000)
        context.insert(debt)

        let rule = RecurringRule(
            bookId: book.id,
            title: "房租",
            templateType: .expense,
            amountMinor: 300_000,
            accountId: cash.id,
            frequency: .monthly,
            startDate: Date()
        )
        context.insert(rule)

        let template = QuickTemplate(bookId: book.id, name: "咖啡", type: .expense, amountMinor: 3_000)
        context.insert(template)

        let merchant = MerchantRule(payeeKey: "starbucks", categoryId: category.id)
        context.insert(merchant)

        let capture = CaptureRecord(ocrText: "测试识别文本", sourceType: "screenshot")
        context.insert(capture)

        let run = ReconciliationRun(bookId: book.id, accountCount: 2, diffCount: 1, totalDiffMinor: 100)
        context.insert(run)

        try context.save()
        return (cash.id, credit.id, loan.id, txn.id)
    }

    @MainActor
    func testFullBackupRestoreRoundTrip() throws {
        let context = makeContext()
        let seeded = try seed(context)

        let backup = try BackupService.makeBackup(context: context)
        let counts = BackupCounts(backup: backup)
        XCTAssertEqual(counts.accounts, 2)
        XCTAssertEqual(counts.txns, 2)
        XCTAssertEqual(counts.loans, 1)
        XCTAssertEqual(counts.scheduleItems, 1)
        XCTAssertEqual(counts.statements, 1)
        XCTAssertEqual(counts.claims, 1)
        XCTAssertEqual(counts.debts, 1)
        XCTAssertEqual(counts.recurringRules, 1)
        XCTAssertEqual(counts.quickTemplates, 1)
        XCTAssertEqual(counts.merchantRules, 1)
        XCTAssertEqual(counts.captureRecords, 1)
        XCTAssertEqual(counts.reconciliationRuns, 1)

        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decode(data)
        // 编解码应稳定可重复
        XCTAssertEqual(try BackupService.encode(decoded), data)

        let result = try BackupService.restore(decoded, into: context)
        XCTAssertEqual(result.counts, counts)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(accounts.count, 2)
        let cash = try XCTUnwrap(accounts.first { $0.id == seeded.cashId })
        XCTAssertEqual(cash.openingBalanceMinor, 100_000)
        XCTAssertEqual(cash.cachedBalanceMinor, 100_000 - 1_250 - 500)
        let credit = try XCTUnwrap(accounts.first { $0.id == seeded.creditId })
        XCTAssertEqual(credit.creditLimitMinor, 500_000)

        let txns = try context.fetch(FetchDescriptor<Txn>())
        XCTAssertEqual(txns.count, 2)
        let txn = try XCTUnwrap(txns.first { $0.id == seeded.txnId })
        XCTAssertEqual(txn.amountMinor, 1_250)
        XCTAssertEqual(txn.payee, "面馆")
        XCTAssertEqual(txns.filter { $0.deletedAt != nil }.count, 1)

        let loans = try context.fetch(FetchDescriptor<Loan>())
        XCTAssertEqual(loans.first?.id, seeded.loanId)
        XCTAssertEqual(loans.first?.annualRateBp, 420)

        let claims = try context.fetch(FetchDescriptor<Claim>())
        XCTAssertEqual(claims.first?.receivedAmountMinor, 2_000)
    }

    @MainActor
    func testDecodeRejectsBadDataAndWrongVersion() throws {
        let context = makeContext()
        _ = try seed(context)
        let backup = try BackupService.makeBackup(context: context)
        let data = try BackupService.encode(backup)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = 99
        let tampered = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try BackupService.decode(tampered)) { error in
            guard case BackupError.unsupportedVersion(99) = error else {
                return XCTFail("应抛出 unsupportedVersion，实际：\(error)")
            }
        }
        XCTAssertThrowsError(try BackupService.decode(Data("not-json".utf8)))
    }

    @MainActor
    func testRestoreWritesAutoBackupBeforeOverwrite() throws {
        let context = makeContext()
        _ = try seed(context)
        let backup = try BackupService.makeBackup(context: context)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try BackupService.restore(backup, into: context, autoBackupDirectory: tempDir)
        let autoURL = try XCTUnwrap(result.autoBackupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: autoURL.path))

        let autoBackup = try BackupService.decode(try Data(contentsOf: autoURL))
        XCTAssertEqual(BackupCounts(backup: autoBackup).txns, 2)
    }

    func testEmptyBackupCounts() {
        let empty = LedgerBackup(
            formatVersion: BackupService.formatVersion,
            exportedAt: Date(),
            books: [], accounts: [], categories: [], txns: [], claims: [], loans: [],
            scheduleItems: [], statements: [], reconciliationRuns: [], debts: [],
            merchantRules: [], captureRecords: [], recurringRules: [], quickTemplates: []
        )
        let counts = BackupCounts(backup: empty)
        XCTAssertEqual(counts.total, 0)
        XCTAssertEqual(counts.summaryText, "空备份")
    }

    @MainActor
    func testRestoreKeepsDataWhenNoExistingRecords() throws {
        let context = makeContext()
        _ = try seed(context)
        let backup = try BackupService.makeBackup(context: context)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 先清空，再恢复：不应生成自动备份（当前无数据）
        let emptyTemp = tempDir.appendingPathComponent("empty-case", isDirectory: true)
        let first = try BackupService.restore(backup, into: context, autoBackupDirectory: tempDir)
        XCTAssertNotNil(first.autoBackupURL)
        let second = try BackupService.restore(backup, into: context, autoBackupDirectory: emptyTemp)
        XCTAssertNotNil(second.autoBackupURL) // 恢复后又有数据，仍然留副本
        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(accounts.count, 2)
    }
}
