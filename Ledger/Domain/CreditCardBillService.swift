import Foundation

/// 一张信用卡当前账单周期的汇总信息（估算 + 已登记账单）
struct CreditCardBillInfo {
    let accountId: UUID
    let periodMonth: String
    let billDate: Date
    let dueDate: Date
    let statementPeriod: DateInterval
    let estimatedAmountMinor: Int64
    /// 最早到期的未结清已登记账单
    let registered: Statement?
}

/// 信用卡账期与金额估算：把原来散在视图和资金计划里的口径收拢到一处。
enum CreditCardBillService {
    static func cycle(for account: Account) -> CreditCardCycle? {
        guard let billDay = account.billDay, let dueDay = account.dueDay,
              billDay > 0, dueDay > 0 else { return nil }
        return CreditCardCycle(billDay: billDay, dueDay: dueDay)
    }

    /// 按最近一个完整账单周期的消费估算本期应还（退款冲减，最低 0）
    static func estimatedBillMinor(
        account: Account,
        cycle: CreditCardCycle,
        txns: [Txn],
        reference: Date
    ) -> Int64? {
        guard let period = cycle.statementPeriod(reference: reference) else { return nil }
        var expense: Int64 = 0
        var refund: Int64 = 0
        for txn in txns where txn.deletedAt == nil
            && txn.accountId == account.id
            && period.contains(txn.occurredAt) {
            if txn.type == .expense {
                expense += txn.amountMinor
            } else if RefundService.isRefund(txn) {
                refund += txn.amountMinor
            }
        }
        let bill = RefundService.netExpense(expenseMinor: expense, refundMinor: refund)
        return bill > 0 ? bill : nil
    }

    /// 最早到期、还没还清的已登记账单
    static func latestUnsettledStatement(for accountId: UUID, statements: [Statement]) -> Statement? {
        statements
            .filter { $0.deletedAt == nil && !$0.isSettled && $0.accountId == accountId }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    static func info(
        for account: Account,
        txns: [Txn],
        statements: [Statement],
        reference: Date = Date()
    ) -> CreditCardBillInfo? {
        guard let cycle = cycle(for: account) else { return nil }
        guard let billDate = cycle.latestBillDate(reference: reference),
              let dueDate = cycle.dueDate(reference: reference),
              let period = cycle.statementPeriod(reference: reference) else {
            return nil
        }

        return CreditCardBillInfo(
            accountId: account.id,
            periodMonth: AppCalendar.monthKey(billDate),
            billDate: billDate,
            dueDate: dueDate,
            statementPeriod: period,
            estimatedAmountMinor: estimatedBillMinor(
                account: account,
                cycle: cycle,
                txns: txns,
                reference: reference
            ) ?? 0,
            registered: latestUnsettledStatement(for: account.id, statements: statements)
        )
    }
}
