import Foundation

struct StatementAllocation: Equatable {
    let statementId: UUID
    let appliedMinor: Int64
}

/// 还款核销：一笔还款按「最早到期优先」自动分摊到未结清的信用卡账单。
enum StatementSettlementService {
    /// 只算分配，不改数据（可单测）
    static func allocate(paymentMinor: Int64, statements: [Statement]) -> [StatementAllocation] {
        guard paymentMinor > 0 else { return [] }
        var remaining = paymentMinor
        var result: [StatementAllocation] = []

        let ordered = statements
            .filter { $0.deletedAt == nil && !$0.isSettled }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        for statement in ordered where remaining > 0 {
            let applied = min(statement.outstandingMinor, remaining)
            guard applied > 0 else { continue }
            result.append(StatementAllocation(statementId: statement.id, appliedMinor: applied))
            remaining -= applied
        }
        return result
    }

    /// 应用到账单：更新已还金额与状态；返回没分完的余额（超出总欠款的部分）
    @discardableResult
    static func apply(paymentMinor: Int64, statements: [Statement], at date: Date = Date()) -> Int64 {
        let allocations = allocate(paymentMinor: paymentMinor, statements: statements)
        var appliedTotal: Int64 = 0
        for allocation in allocations {
            guard let statement = statements.first(where: { $0.id == allocation.statementId }) else { continue }
            statement.paidAmountMinor += allocation.appliedMinor
            statement.refreshStatus(reference: date)
            appliedTotal += allocation.appliedMinor
        }
        return max(0, paymentMinor - appliedTotal)
    }
}
