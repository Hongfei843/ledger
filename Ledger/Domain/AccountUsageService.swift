import Foundation

/// 记账页的账户排序与余额展示逻辑（纯逻辑，方便单测）。
enum AccountUsageService {
    /// 账户使用频次：转账两边都算一次，忽略已删除流水
    static func usageCounts(txns: [Txn]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for txn in txns where txn.deletedAt == nil {
            counts[txn.accountId, default: 0] += 1
            if let counter = txn.counterAccountId {
                counts[counter, default: 0] += 1
            }
        }
        return counts
    }

    /// 用得多的在前；次数相同按 sortOrder，再按名称兜底
    static func orderedAccounts(_ accounts: [Account], usage: [UUID: Int]) -> [Account] {
        accounts.sorted { lhs, rhs in
            let left = usage[lhs.id] ?? 0
            let right = usage[rhs.id] ?? 0
            if left != right { return left > right }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name < rhs.name
        }
    }

    /// 账户当前余额（资产正、负债负）
    static func balanceMap(accounts: [Account], txns: [Txn]) -> [UUID: Int64] {
        let live = txns.filter { $0.deletedAt == nil }
        var map: [UUID: Int64] = [:]
        for account in accounts where account.deletedAt == nil {
            map[account.id] = BalanceService.balance(
                of: account,
                transactions: live,
                openingBalanceMinor: account.openingBalanceMinor
            )
        }
        return map
    }

    /// 账户 chip 的副标题：信用卡显示可用额度，负债显示欠款，资产显示余额
    static func subtitle(account: Account, balanceMinor: Int64) -> String {
        if account.type.isCreditLike, let limit = account.creditLimitMinor {
            return "可用 " + Money.format(limit + balanceMinor)
        }
        if account.type.isLiability {
            return balanceMinor < 0 ? "欠 " + Money.format(-balanceMinor) : "余额 " + Money.format(balanceMinor)
        }
        return "余额 " + Money.format(balanceMinor)
    }
}
