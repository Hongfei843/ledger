import Foundation

/// 某个月的净资产快照（截止到 cutoff 当天）
struct NetWorthPoint: Identifiable, Equatable {
    let id: String
    let monthStart: Date
    let cutoff: Date
    let assetsMinor: Int64
    let liabilitiesMinor: Int64

    var netWorthMinor: Int64 { assetsMinor - liabilitiesMinor }
}

/// 净资产历史：按月末重算每个账户余额，纯本地、可单测。
/// 口径与 `BalanceService.netWorth` 保持一致：排除贷款账户、归档账户、不计入净资产的账户。
enum NetWorthHistory {
    static func monthly(
        months: Int,
        endingAt: Date = Date(),
        accounts: [Account],
        transactions: [Txn]
    ) -> [NetWorthPoint] {
        guard months > 0 else { return [] }
        let calendar = AppCalendar.gregorian
        let liveTxns = transactions.filter { $0.deletedAt == nil }
        let currentMonthStart = AppCalendar.startOfMonth(endingAt)
        var points: [NetWorthPoint] = []

        for offset in stride(from: months - 1, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else { continue }

            let cutoff: Date
            if offset == 0 {
                cutoff = endingAt
            } else if let nextStart = calendar.date(byAdding: .month, value: 1, to: monthStart) {
                cutoff = nextStart
            } else {
                continue
            }

            var assets: Int64 = 0
            var liabilities: Int64 = 0

            for account in accounts where account.deletedAt == nil
                && !account.isArchived
                && account.includeInNetWorth
                && account.type != .loan {
                let balance = balance(of: account, transactions: liveTxns, before: cutoff)
                if account.type.isLiability {
                    if balance < 0 {
                        liabilities += -balance
                    } else {
                        assets += balance
                    }
                } else {
                    assets += balance
                }
            }

            points.append(
                NetWorthPoint(
                    id: AppCalendar.monthKey(monthStart),
                    monthStart: monthStart,
                    cutoff: cutoff,
                    assetsMinor: assets,
                    liabilitiesMinor: liabilities
                )
            )
        }
        return points
    }

    private static func balance(of account: Account, transactions: [Txn], before cutoff: Date) -> Int64 {
        var balance = account.openingBalanceMinor
        for txn in transactions where txn.occurredAt < cutoff {
            switch txn.type {
            case .transfer:
                if txn.accountId == account.id { balance -= txn.amountMinor }
                if txn.counterAccountId == account.id { balance += txn.amountMinor }
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
}
