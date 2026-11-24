import Foundation

/// 余额计算：资产为正、负债为负，统一一个公式。
/// balance = opening + Σincome − Σexpense + ΣtransferIn − ΣtransferOut + Σadjustment
enum BalanceService {
    static func balance(of account: Account, transactions: [Txn], openingBalanceMinor: Int64) -> Int64 {
        var balance = openingBalanceMinor
        for txn in transactions where txn.deletedAt == nil {
            switch txn.type {
            case .transfer:
                if txn.accountId == account.id {
                    balance -= txn.amountMinor
                }
                if txn.counterAccountId == account.id {
                    balance += txn.amountMinor
                }
            case .expense:
                if txn.accountId == account.id { balance -= txn.amountMinor }
            case .income:
                if txn.accountId == account.id { balance += txn.amountMinor }
            case .adjustment:
                if txn.accountId == account.id { balance += txn.amountMinor }
            case .loanPayment:
                break
            }
        }
        return balance
    }

    /// 就地刷新账户缓存余额
    static func refresh(account: Account, transactions: [Txn]) {
        account.cachedBalanceMinor = balance(
            of: account,
            transactions: transactions,
            openingBalanceMinor: account.openingBalanceMinor
        )
        account.updatedAt = Date()
    }

    /// 净资产 = Σ 资产账户 + Σ 负债账户（负债为负）
    static func netWorth(accounts: [Account], transactions: [Txn]) -> Int64 {
        accounts
            .filter { $0.deletedAt == nil && !$0.isArchived && $0.includeInNetWorth && $0.type != .loan }
            .reduce(Int64(0)) { partial, account in
                partial + balance(of: account, transactions: transactions, openingBalanceMinor: account.openingBalanceMinor)
            }
    }
}
