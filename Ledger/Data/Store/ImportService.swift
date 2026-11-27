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

enum ImportError: LocalizedError {
    case invalidDefaultAccount
    case invalidCategory
    case saveFailed(String)
    case balanceRefreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDefaultAccount:
            return "默认账户不属于当前账本，或已归档/删除。请重新选择当前账本中的有效账户。"
        case .invalidCategory:
            return "导入分类不属于当前账本，或已归档/删除。"
        case .saveFailed(let message):
            return "导入保存失败，未确认写入数据：\(message)"
        case .balanceRefreshFailed(let message):
            return "流水已导入，但余额缓存刷新失败。请重新打开 App 核对余额：\(message)"
        }
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
    ) throws -> ImportSummary {
        var summary = ImportSummary()

        let existingTxns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        // 软删除的记录不应继续占用 externalId，否则删掉后无法重新导入同一批账单。
        var knownExternalIds = Set(existingTxns.filter { $0.deletedAt == nil }.compactMap { $0.externalId })

        let allCategories = ((try? context.fetch(FetchDescriptor<Category>())) ?? []).filter { $0.bookId == bookId }
        var categoryIndex: [String: Category] = [:]
        for category in allCategories where category.deletedAt == nil && !category.isArchived {
            categoryIndex["\(category.kind.rawValue)|\(category.name)"] = category
        }

        let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard allAccounts.contains(where: {
            $0.id == defaultAccountId && $0.bookId == bookId
                && $0.deletedAt == nil && !$0.isArchived && !$0.isSystem
        }) else {
            throw ImportError.invalidDefaultAccount
        }
        var accountIndex: [String: Account] = [:]
        for account in allAccounts where account.deletedAt == nil && !account.isArchived && account.bookId == bookId {
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
                      let matched = CategoryMatcher.match(
                          name: record.primaryCategory,
                          kind: kind,
                          categories: allCategories.filter { $0.deletedAt == nil && !$0.isArchived }
                      ) {
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

        do {
            try context.save()
        } catch {
            context.rollback()
            throw ImportError.saveFailed(error.localizedDescription)
        }

        let allTxns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        let refreshedAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        BalanceService.refreshAll(accounts: refreshedAccounts, transactions: allTxns)
        do {
            try context.save()
        } catch {
            throw ImportError.balanceRefreshFailed(error.localizedDescription)
        }

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
    ) throws -> Int {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard accounts.contains(where: {
            $0.id == accountId && $0.bookId == bookId
                && $0.deletedAt == nil && !$0.isArchived && !$0.isSystem
        }) else {
            throw ImportError.invalidDefaultAccount
        }
        if let categoryId {
            let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
            guard categories.contains(where: {
                $0.id == categoryId && $0.bookId == bookId && $0.deletedAt == nil && !$0.isArchived
            }) else {
                throw ImportError.invalidCategory
            }
        }
        let existing = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        var knownExternalIds = Set(existing.filter { $0.deletedAt == nil }.compactMap { $0.externalId })
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

        do {
            try context.save()
        } catch {
            context.rollback()
            throw ImportError.saveFailed(error.localizedDescription)
        }

        let allTxns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: allTxns)
        do {
            try context.save()
        } catch {
            throw ImportError.balanceRefreshFailed(error.localizedDescription)
        }

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
