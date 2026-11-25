import XCTest
import Foundation
@testable import Ledger

final class QuickTemplateTests: XCTestCase {
    private let bookId = UUID()

    private func makeAccounts() -> (active: Account, archived: Account) {
        let active = Account(bookId: bookId, name: "招行", type: .debit)
        let archived = Account(bookId: bookId, name: "旧卡", type: .debit)
        archived.isArchived = true
        return (active, archived)
    }

    private func makeCategories() -> (live: Ledger.Category, deleted: Ledger.Category) {
        let live = Category(bookId: bookId, name: "餐饮", kind: .expense, iconEmoji: "🍜")
        let deleted = Category(bookId: bookId, name: "旧分类", kind: .expense, iconEmoji: "🗑")
        deleted.deletedAt = Date()
        return (live, deleted)
    }

    func testSelectionKeepsValidReferences() {
        let (activeAccount, _) = makeAccounts()
        let (liveCategory, _) = makeCategories()
        let template = QuickTemplate(
            bookId: bookId,
            name: "咖啡",
            type: .expense,
            amountMinor: 3000,
            accountId: activeAccount.id,
            categoryId: liveCategory.id,
            payee: "星巴克",
            note: "早餐"
        )

        let selection = QuickTemplateService.selection(
            from: template,
            accounts: [activeAccount],
            categories: [liveCategory]
        )
        XCTAssertEqual(selection?.type, TxnType.expense)
        XCTAssertEqual(selection?.amountMinor, 3000)
        XCTAssertEqual(selection?.accountId, activeAccount.id)
        XCTAssertEqual(selection?.categoryId, liveCategory.id)
        XCTAssertEqual(selection?.payee, "星巴克")
    }

    func testSelectionDropsArchivedAccountAndDeletedCategory() {
        let (activeAccount, archivedAccount) = makeAccounts()
        let (liveCategory, deletedCategory) = makeCategories()
        let template = QuickTemplate(
            bookId: bookId,
            name: "打车",
            type: .expense,
            amountMinor: 1200,
            accountId: archivedAccount.id,
            categoryId: deletedCategory.id
        )

        let selection = QuickTemplateService.selection(
            from: template,
            accounts: [activeAccount, archivedAccount],
            categories: [liveCategory, deletedCategory]
        )
        XCTAssertNil(selection?.accountId)
        XCTAssertNil(selection?.categoryId)
        XCTAssertEqual(selection?.amountMinor, 1200)
    }

    func testDeletedTemplateProducesNoSelection() {
        let template = QuickTemplate(bookId: bookId, name: "旧模板", type: .expense)
        template.deletedAt = Date()
        XCTAssertNil(QuickTemplateService.selection(from: template, accounts: [], categories: []))
    }

    func testZeroAmountBecomesNil() {
        let template = QuickTemplate(bookId: bookId, name: "无金额", type: .expense, amountMinor: 0)
        XCTAssertNil(QuickTemplateService.selection(from: template, accounts: [], categories: [])?.amountMinor)
    }
}
