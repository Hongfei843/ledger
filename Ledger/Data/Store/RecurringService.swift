import Foundation
import SwiftData

/// 把周期性规则落成真实流水。
enum RecurringService {
    struct RunResult {
        var createdCount: Int = 0
        var ruleTitles: [String] = []
    }

    @discardableResult
    static func run(
        context: ModelContext,
        today: Date = Date()
    ) -> RunResult {
        var result = RunResult()

        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        let active = rules.filter { $0.deletedAt == nil && !$0.isPaused && $0.autoCreate }
        guard !active.isEmpty else { return result }

        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let txns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        var touchedAccounts = Set<UUID>()

        for rule in active {
            guard rule.amountMinor > 0,
                  let sourceAccount = accounts.first(where: {
                      $0.id == rule.accountId && $0.deletedAt == nil && !$0.isArchived && $0.bookId == rule.bookId
                  }) else { continue }
            if rule.templateType == .transfer {
                guard let targetId = rule.counterAccountId, targetId != sourceAccount.id,
                      accounts.contains(where: {
                          $0.id == targetId && $0.deletedAt == nil && !$0.isArchived && $0.bookId == rule.bookId
                      }) else { continue }
            }
            let dates = RecurringEngine.dueDates(rule: rule, upTo: today)
            guard !dates.isEmpty else { continue }

            for date in dates {
                let txn = Txn(
                    bookId: rule.bookId,
                    type: rule.templateType,
                    amountMinor: rule.amountMinor,
                    accountId: rule.accountId,
                    occurredAt: date,
                    categoryId: rule.categoryId,
                    counterAccountId: rule.counterAccountId,
                    note: rule.note ?? rule.title,
                    source: .recurring
                )
                context.insert(txn)
                touchedAccounts.insert(rule.accountId)
                if let counter = rule.counterAccountId {
                    touchedAccounts.insert(counter)
                }
                result.createdCount += 1
            }

            if let last = dates.last,
               let next = RecurringEngine.nextDate(after: last, frequency: rule.frequency, interval: rule.interval) {
                rule.nextDate = next
            }
            rule.updatedAt = Date()
            result.ruleTitles.append(rule.title)
        }

        try? context.save()

        if !touchedAccounts.isEmpty {
            let latest = (try? context.fetch(FetchDescriptor<Txn>())) ?? txns
            BalanceService.refreshAll(accounts: accounts, transactions: latest)
            try? context.save()
        }

        return result
    }
}
