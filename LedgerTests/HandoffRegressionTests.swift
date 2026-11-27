import XCTest
import SwiftData
import Foundation
@testable import Ledger

/// 本轮接手修复的回归用例：每条都锁定一个曾经会算错或写错的具体场景。
final class HandoffRegressionTests: XCTestCase {
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

    // MARK: - 备份兼容

    @MainActor
    func testMissingIncludeInNetWorthDefaultsToTrue() throws {
        let context = makeContext()
        let book = Book()
        let account = Account(bookId: book.id, name: "现金", type: .cash, openingBalanceMinor: 10_000)
        context.insert(book)
        context.insert(account)

        let backup = try BackupService.makeBackup(context: context)
        var object = try JSONSerialization.jsonObject(with: BackupService.encode(backup)) as! [String: Any]
        var accounts = object["accounts"] as! [[String: Any]]
        accounts[0].removeValue(forKey: "includeInNetWorth")
        object["accounts"] = accounts
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try BackupService.decode(data)
        XCTAssertEqual(decoded.accounts.first?.includeInNetWorth, true,
                       "旧备份缺字段时不能把账户排除出净资产")
    }

    @MainActor
    func testFormatVersionOneCanBeRestoredEndToEnd() throws {
        let context = makeContext()
        let book = Book()
        let account = Account(bookId: book.id, name: "储蓄卡", type: .debit, openingBalanceMinor: 50_000)
        context.insert(book)
        context.insert(account)

        var backup = try BackupService.makeBackup(context: context)
        backup.formatVersion = 1
        let decoded = try BackupService.decodeDetailed(BackupService.encode(backup))
        XCTAssertEqual(decoded.version, 1)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-restore-\(UUID().uuidString)", isDirectory: true)
        let result = try BackupService.restore(decoded.backup, into: context, autoBackupDirectory: folder)
        XCTAssertEqual(result.counts.accounts, 1)
        XCTAssertTrue(decoded.backup.accounts.first?.includeInNetWorth == true)
    }

    // MARK: - 报销

    @MainActor
    func testReimbursementRejectsAmountAboveAdvance() throws {
        let context = makeContext()
        let book = Book()
        let account = Account(bookId: book.id, name: "储蓄卡", type: .debit)
        let claim = Claim(bookId: book.id, title: "2026-11 报销", periodMonth: "2026-11")
        context.insert(book)
        context.insert(account)
        context.insert(claim)

        let income = ReimbursementSettlementService.receive(
            claim: claim,
            totalMinor: 5_000,
            amountMinor: 6_000,
            accountId: account.id,
            shortfallCategoryId: nil,
            context: context
        )
        XCTAssertNil(income, "到账超过垫付总额必须拒绝")
        XCTAssertEqual(claim.status, .draft, "拒绝后报销单状态不能改变")
        let txns = try context.fetch(FetchDescriptor<Txn>())
        XCTAssertTrue(txns.isEmpty, "拒绝后不能留下任何流水")
    }

    func testPendingRefundDeductedInAllCalibers() {
        let bookId = UUID()
        let accountId = UUID()
        let monthKey = AppCalendar.monthKey(Date())
        let claim = Claim(bookId: bookId, title: "报销", periodMonth: monthKey)
        let expense = Txn(
            bookId: bookId, type: .expense, amountMinor: 5_000,
            accountId: accountId, occurredAt: Date()
        )
        expense.isReimbursable = true
        expense.claimId = claim.id
        let refund = Txn(
            bookId: bookId, type: .income, amountMinor: 2_000,
            accountId: accountId, occurredAt: Date()
        )
        refund.refundOfTxnId = expense.id

        for caliber in StatsCaliber.allCases {
            let summary = StatsEngine.summary(
                range: AppCalendar.monthInterval(containing: Date()),
                caliber: caliber,
                txns: [expense, refund],
                claims: [claim]
            )
            XCTAssertEqual(summary.pendingMinor, 3_000,
                           "\(caliber.displayName)口径的待报销金额应与退款净额一致")
        }
    }

    func testClaimReportCreditsReceiptToActualMonth() {
        let bookId = UUID()
        let now = Date()
        let lastMonth = AppCalendar.gregorian.date(byAdding: .month, value: -1, to: now) ?? now
        let claim = Claim(
            bookId: bookId,
            title: "跨月报销",
            periodMonth: AppCalendar.monthKey(lastMonth)
        )
        claim.status = .reimbursed
        claim.reimbursedAt = now
        claim.receivedAmountMinor = 5_000

        let report = ClaimReportBuilder.build(
            monthAnchor: now, claims: [claim], txns: [], categories: []
        )
        XCTAssertEqual(report.receivedMinor, 5_000, "到账应计入实际到账月份")
    }

    // MARK: - 导入 / 统计 / 投资

    func testBillCSVRecognizesTransactionDateHeader() throws {
        let text = "交易日期,收支,金额\n2026-03-15,支出,38.00\n"
        let result = try BillCSVParser.parse(text: text)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows.first?.amountMinor, 3_800)
    }

    func testUnknownCostNeverBecomesInvestmentProfit() {
        let bookId = UUID()
        let known = Account(bookId: bookId, name: "已知成本", type: .investment, openingBalanceMinor: 10_000)
        known.positionCostMinor = 10_000
        let unknown = Account(bookId: bookId, name: "未知成本", type: .investment, openingBalanceMinor: 100_000)

        let portfolio = InvestmentService.portfolio(accounts: [known, unknown], txns: [])
        XCTAssertNil(portfolio.profitMinor,
                     "存在未填成本的持仓时，汇总收益不能把它的市值当成利润")
        XCTAssertEqual(portfolio.valueMinor, 110_000)
    }

    func testRefundOffsetsOriginalExpenseCategory() {
        let bookId = UUID()
        let accountId = UUID()
        let food = Category(bookId: bookId, name: "餐饮", kind: .expense)
        let traffic = Category(bookId: bookId, name: "交通", kind: .expense)
        let expense = Txn(
            bookId: bookId, type: .expense, amountMinor: 10_000,
            accountId: accountId, occurredAt: Date(), categoryId: food.id
        )
        let refund = Txn(
            bookId: bookId, type: .income, amountMinor: 3_000,
            accountId: accountId, occurredAt: Date(), categoryId: traffic.id
        )
        refund.refundOfTxnId = expense.id

        let slices = StatsEngine.byCategory(
            range: AppCalendar.monthInterval(containing: Date()),
            caliber: .personal,
            txns: [expense, refund],
            claims: [],
            categories: [food, traffic]
        )
        XCTAssertEqual(slices.first(where: { $0.name == "餐饮" })?.amountMinor, 7_000)
        XCTAssertNil(slices.first(where: { $0.name == "交通" }),
                     "退款被改过分类时不应冲到错误分类")
    }

    func testTotalsIncludeTransactionAggregation() {
        let bookId = UUID()
        let otherBookId = UUID()
        let cash = Account(bookId: bookId, name: "现金", type: .cash, openingBalanceMinor: 10_000)
        let credit = Account(bookId: bookId, name: "信用卡", type: .credit, openingBalanceMinor: -2_000)
        let excluded = Account(bookId: bookId, name: "不计入", type: .cash, openingBalanceMinor: 99_999)
        excluded.includeInNetWorth = false
        let foreign = Account(bookId: otherBookId, name: "别的账本", type: .cash, openingBalanceMinor: 50_000)

        func txn(_ type: TxnType, _ amount: Int64, _ accountId: UUID,
                 counter: UUID? = nil, book: UUID = bookId) -> Txn {
            Txn(bookId: book, type: type, amountMinor: amount,
                accountId: accountId, occurredAt: Date(), counterAccountId: counter)
        }
        let txns = [
            txn(.income, 5_000, cash.id),
            txn(.expense, 1_000, cash.id),
            txn(.transfer, 2_000, cash.id, counter: credit.id),
            txn(.adjustment, 500, credit.id),
            txn(.loanPayment, 7_000, cash.id),
            txn(.income, 100_000, cash.id, book: otherBookId)
        ]

        let totals = BalanceService.totals(
            accounts: [cash, credit, excluded, foreign], transactions: txns, bookId: bookId
        )
        // 现金 10000+5000-1000-2000=12000；信用卡 -2000+2000+500=500。
        XCTAssertEqual(totals.assetsMinor, 12_500)
        XCTAssertEqual(totals.liabilitiesMinor, 0)
        XCTAssertEqual(totals.netWorthMinor, 12_500)
    }
}
