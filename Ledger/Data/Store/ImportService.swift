import Foundation
import SwiftData

struct ImportSummary {
    var inserted: Int = 0
    var skippedDuplicate: Int = 0
    var skippedInvalid: Int = 0
    var categoriesCreated: Int = 0
    var categoriesMatched: Int = 0
    var accountsCreated: Int = 0

    var description: String {
        var parts = ["导入 \(inserted) 条"]
        if categoriesMatched > 0 { parts.append("\(categoriesMatched) 类自动归类") }
        if categoriesCreated > 0 { parts.append("新建 \(categoriesCreated) 类") }
        if skippedDuplicate > 0 { parts.append("重复跳过 \(skippedDuplicate) 条") }
        if skippedInvalid > 0 { parts.append("无效 \(skippedInvalid) 条") }
        return parts.joined(separator: "，")
    }
}

enum ImportService {
    /// 把解析后的 Cookie 记录写入本地库。幂等：靠 externalId 去重。
    @discardableResult
    static func importCookie(
        records: [CookieRecord],
        defaultAccountId: UUID,
        bookId: UUID,
        context: ModelContext,
        autoMatchCategories: Bool = true
    ) -> ImportSummary {
        var summary = ImportSummary()

        let existingTxns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        var knownExternalIds = Set(existingTxns.compactMap { $0.externalId })

        let allCategories = ((try? context.fetch(FetchDescriptor<Category>())) ?? []).filter { $0.bookId == bookId }
        var categoryIndex: [String: Category] = [:]
        for category in allCategories where category.deletedAt == nil {
            categoryIndex["\(category.kind.rawValue)|\(category.name)"] = category
        }

        let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var accountIndex: [String: Account] = [:]
        for account in allAccounts where account.deletedAt == nil && account.bookId == bookId {
            accountIndex[account.name] = account
        }

        var maxSort = (allCategories.map { $0.sortOrder }.max() ?? 0) + 1

        for record in records {
            if let externalId = record.externalId {
                if knownExternalIds.contains(externalId) {
                    summary.skippedDuplicate += 1
                    continue
                }
            }

            let kind: CategoryKind = record.isIncome ? .income : .expense
            let categoryKey = "\(kind.rawValue)|\(record.primaryCategory)"
            let category: Category
            if let existing = categoryIndex[categoryKey] {
                category = existing
            } else if autoMatchCategories,
                      let matched = CategoryMatcher.match(name: record.primaryCategory, kind: kind, categories: allCategories) {
                // 外部叫法（美食 / App 订阅 / 电费）落到已有分类，避免分类表膨胀
                category = matched
                categoryIndex[categoryKey] = matched
                summary.categoriesMatched += 1
            } else {
                let created = Category(
                    bookId: bookId,
                    name: record.primaryCategory,
                    kind: kind,
                    iconEmoji: record.emoji ?? (kind == .income ? "💰" : "📦"),
                    sortOrder: maxSort
                )
                maxSort += 1
                context.insert(created)
                categoryIndex[categoryKey] = created
                summary.categoriesCreated += 1
                category = created
            }

            var accountId = defaultAccountId
            if let name = record.accountName {
                if let existing = accountIndex[name] {
                    accountId = existing.id
                } else {
                    let created = Account(
                        bookId: bookId,
                        name: name,
                        type: inferAccountType(from: name),
                        iconEmoji: "💳",
                        sortOrder: 90
                    )
                    created.bankId = BankPreset.match(name: name)?.id
                    context.insert(created)
                    accountIndex[name] = created
                    summary.accountsCreated += 1
                    accountId = created.id
                }
            }

            let txn = Txn(
                bookId: bookId,
                type: record.isIncome ? .income : .expense,
                amountMinor: record.amountMinor,
                accountId: accountId,
                occurredAt: record.occurredAt,
                categoryId: category.id,
                payee: nil,
                note: record.note,
                source: .imported
            )
            txn.externalId = record.externalId
            txn.isReimbursable = record.needReimbursement

            context.insert(txn)
            if let externalId = record.externalId {
                knownExternalIds.insert(externalId)
            }
            summary.inserted += 1
        }

        try? context.save()

        let allTxns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        let refreshedAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        BalanceService.refreshAll(accounts: refreshedAccounts, transactions: allTxns)
        try? context.save()

        return summary
    }

    /// 补录「账单里有、App 里没有」的行
    @discardableResult
    static func importBillRows(
        _ rows: [BillRow],
        accountId: UUID,
        bookId: UUID,
        categoryId: UUID?,
        context: ModelContext
    ) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        var knownExternalIds = Set(existing.compactMap { $0.externalId })
        var inserted = 0

        for row in rows {
            if let externalId = row.externalId, knownExternalIds.contains(externalId) {
                continue
            }
            let txn = Txn(
                bookId: bookId,
                type: row.isIncome ? .income : .expense,
                amountMinor: row.amountMinor,
                accountId: accountId,
                occurredAt: row.occurredAt,
                categoryId: categoryId,
                payee: row.counterparty,
                note: row.subject,
                source: .imported
            )
            txn.externalId = row.externalId
            context.insert(txn)
            if let externalId = row.externalId {
                knownExternalIds.insert(externalId)
            }
            inserted += 1
        }

        try? context.save()

        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let allTxns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: allTxns)
        try? context.save()

        return inserted
    }

    static func inferAccountType(from name: String) -> AccountType {        if name.contains("信用卡") { return .credit }
        if name.contains("花呗") || name.contains("白条") { return .bnpl }
        if name.contains("支付宝") || name.contains("微信") || name.contains("零钱") { return .ewallet }
        if name.contains("现金") { return .cash }
        if name.contains("公积金") { return .providentFund }
        return .debit
    }
}
