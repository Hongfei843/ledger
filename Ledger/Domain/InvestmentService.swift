import Foundation

/// 投资账户的持仓/收益计算（纯逻辑）。
struct InvestmentPosition {
    let accountId: UUID
    let valueMinor: Int64
    let costMinor: Int64

    /// 浮动盈亏；没填成本时为 nil（不假装知道收益）
    var profitMinor: Int64? {
        guard costMinor > 0 else { return nil }
        return valueMinor - costMinor
    }

    /// 收益率（百分比）；成本 ≤ 0 时返回 nil
    var ratePercent: Double? {
        guard let profitMinor else { return nil }
        return Double(profitMinor) / Double(costMinor) * 100
    }
}

struct InvestmentPortfolio {
    let valueMinor: Int64
    let costMinor: Int64
    let positions: [InvestmentPosition]

    var profitMinor: Int64? {
        guard costMinor > 0 else { return nil }
        return valueMinor - costMinor
    }

    var ratePercent: Double? {
        guard let profitMinor else { return nil }
        return Double(profitMinor) / Double(costMinor) * 100
    }
}

enum InvestmentService {
    /// 单个投资账户：市值 = 账户余额；成本 = positionCostMinor（未填则不计算收益）
    static func position(for account: Account, txns: [Txn]) -> InvestmentPosition? {
        guard account.type == .investment else { return nil }
        let value = BalanceService.balance(
            of: account,
            transactions: txns.filter { $0.deletedAt == nil },
            openingBalanceMinor: account.openingBalanceMinor
        )
        let cost = account.positionCostMinor ?? 0
        return InvestmentPosition(accountId: account.id, valueMinor: value, costMinor: cost)
    }

    static func portfolio(accounts: [Account], txns: [Txn]) -> InvestmentPortfolio {
        let live = txns.filter { $0.deletedAt == nil }
        let positions = accounts
            .filter { $0.deletedAt == nil && !$0.isArchived && $0.type == .investment }
            .compactMap { position(for: $0, txns: live) }
        let value = positions.reduce(Int64(0)) { $0 + $1.valueMinor }
        let cost = positions.reduce(Int64(0)) { $0 + $1.costMinor }
        return InvestmentPortfolio(valueMinor: value, costMinor: cost, positions: positions)
    }

    /// 转入投资账户：持仓成本增加
    static func costAfterContribution(current: Int64?, amount: Int64) -> Int64 {
        max(0, (current ?? 0) + max(0, amount))
    }

    /// 转出投资账户：持仓成本减少（不会小于 0）
    static func costAfterWithdrawal(current: Int64?, amount: Int64) -> Int64 {
        max(0, (current ?? 0) - max(0, amount))
    }
}
