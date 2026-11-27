import Foundation

/// 余额计算：资产为正、负债为负，统一一个公式。
/// balance = opening + Σincome − Σexpense + ΣtransferIn − ΣtransferOut + Σadjustment
/// 同一批账户下的资产、负债与净资产。总资产 - 总负债始终等于净资产。
struct NetWorthTotals: Equatable {
    var assetsMinor: Int64
    var liabilitiesMinor: Int64

    var netWorthMinor: Int64 { assetsMinor - liabilitiesMinor }
}

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

    /// 刷新所有账户（增删改流水后调用）
    static func refreshAll(accounts: [Account], transactions: [Txn]) {
        for account in accounts where account.deletedAt == nil {
            refresh(account: account, transactions: transactions)
        }
    }

    /// 净资产口径的唯一入口：归档、已删除、主动排除及贷款系统账户均不参与。
    /// 正余额计入资产、负余额计入负债，避免信用卡溢缴款被错误算成负债。
    static func totals(
        accounts: [Account],
        transactions: [Txn],
        bookId: UUID? = nil
    ) -> NetWorthTotals {
        let eligible = accounts.filter { account in
            (bookId == nil || account.bookId == bookId)
                && account.deletedAt == nil
                && !account.isArchived
                && account.includeInNetWorth
                && account.type != .loan
        }
        var balances = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0.openingBalanceMinor) })
        for txn in transactions where txn.deletedAt == nil && (bookId == nil || txn.bookId == bookId) {
            switch txn.type {
            case .expense:
                if balances[txn.accountId] != nil { balances[txn.accountId] = (balances[txn.accountId] ?? 0) - txn.amountMinor }
            case .income:
                if balances[txn.accountId] != nil { balances[txn.accountId] = (balances[txn.accountId] ?? 0) + txn.amountMinor }
            case .transfer:
                if balances[txn.accountId] != nil { balances[txn.accountId] = (balances[txn.accountId] ?? 0) - txn.amountMinor }
                if let targetId = txn.counterAccountId, balances[targetId] != nil {
                    balances[targetId] = (balances[targetId] ?? 0) + txn.amountMinor
                }
            case .adjustment:
                if balances[txn.accountId] != nil { balances[txn.accountId] = (balances[txn.accountId] ?? 0) + txn.amountMinor }
            case .loanPayment:
                break
            }
        }

        var assets: Int64 = 0
        var liabilities: Int64 = 0
        for balance in balances.values {
            if balance >= 0 { assets += balance } else { liabilities += -balance }
        }
        return NetWorthTotals(assetsMinor: assets, liabilitiesMinor: liabilities)
    }

    static func netWorth(accounts: [Account], transactions: [Txn]) -> Int64 {
        totals(accounts: accounts, transactions: transactions).netWorthMinor
    }

    /// 负债账户在校准界面填写「实际欠款」，领域层内部仍使用带符号余额。
    /// 溢缴款可输入负数，转换后即正余额。
    static func signedBalance(fromActualInput amountMinor: Int64, accountType: AccountType) -> Int64 {
        accountType.isLiability ? -amountMinor : amountMinor
    }

    /// 把内部带符号余额转为用户熟悉的展示方式：信用卡欠款显示正数。
    static func displayBalance(_ amountMinor: Int64, accountType: AccountType) -> Int64 {
        accountType.isLiability ? -amountMinor : amountMinor
    }
}
