import Foundation

/// 退款计算：把「退款」看成原支出的冲减，而不是收入。
/// 退款流水本身是一条 income，但通过 refundOfTxnId 挂在原支出上。
enum RefundService {
    static func isRefund(_ txn: Txn) -> Bool {
        txn.type == .income && txn.refundOfTxnId != nil
    }

    /// 某笔支出已退款合计（只算未删除的退款流水）
    static func refundedMinor(of txn: Txn, all: [Txn]) -> Int64 {
        all
            .filter { $0.deletedAt == nil && isRefund($0) && $0.refundOfTxnId == txn.id }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    /// 某笔支出的退款流水明细，按时间倒序
    static func refunds(of txn: Txn, all: [Txn]) -> [Txn] {
        all
            .filter { $0.deletedAt == nil && isRefund($0) && $0.refundOfTxnId == txn.id }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    /// 还能退多少（不超过原金额）
    static func remainingRefundableMinor(of txn: Txn, all: [Txn]) -> Int64 {
        guard txn.type == .expense else { return 0 }
        return max(0, txn.amountMinor - refundedMinor(of: txn, all: all))
    }

    /// 净支出 = 支出 - 退款，最低 0（防止跨月退款把当月支出冲成负数）
    static func netExpense(expenseMinor: Int64, refundMinor: Int64) -> Int64 {
        max(0, expenseMinor - max(0, refundMinor))
    }
}
