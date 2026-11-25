import Foundation

/// 资金计划里的一条未来现金变动。正数=流入，负数=流出。
enum CashFlowKind: String, Equatable {
    case loan
    case creditCard
    case recurring
    case receivable
    case payable

    var displayName: String {
        switch self {
        case .loan: return "贷款"
        case .creditCard: return "信用卡"
        case .recurring: return "周期"
        case .receivable: return "应收"
        case .payable: return "应付"
        }
    }

    var symbolName: String {
        switch self {
        case .loan: return "house"
        case .creditCard: return "creditcard"
        case .recurring: return "arrow.triangle.2.circlepath"
        case .receivable: return "arrow.down.left.circle"
        case .payable: return "arrow.up.right.circle"
        }
    }
}

struct CashFlowEvent: Identifiable, Equatable {
    let id: String
    let date: Date
    let title: String
    let kind: CashFlowKind
    /// 正=流入，负=流出（单位：分）
    let amountMinor: Int64
}

struct CashFlowPlan {
    let startDate: Date
    let endDate: Date
    /// 当前可动用资金（现金/储蓄卡/电子钱包/储值卡，不含负债与公积金）
    let startingBalanceMinor: Int64
    let events: [CashFlowEvent]

    var outflowMinor: Int64 {
        events.filter { $0.amountMinor < 0 }.reduce(Int64(0)) { $0 + (-$1.amountMinor) }
    }

    var inflowMinor: Int64 {
        events.filter { $0.amountMinor > 0 }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    var netMinor: Int64 { inflowMinor - outflowMinor }

    var endingBalanceMinor: Int64 { startingBalanceMinor + netMinor }
}

/// 资金计划：把「已知的未来现金流出/流入」合成一条时间线。
/// 只做可解释的估算：已登记信用卡账单用真实金额；没登记的按账单周期消费估算。
enum CashFlowForecast {
    static func plan(
        from startDate: Date = Date(),
        days: Int = 30,
        accounts: [Account],
        transactions: [Txn],
        loans: [Loan] = [],
        loanScheduleItems: [LoanScheduleItem] = [],
        recurringRules: [RecurringRule] = [],
        debts: [Debt] = [],
        statements: [Statement] = [],
        calendar: Calendar = AppCalendar.gregorian
    ) -> CashFlowPlan {
        let liveTxns = transactions.filter { $0.deletedAt == nil }
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.date(byAdding: .day, value: max(1, days), to: startDay) ?? startDay

        func inWindow(_ date: Date) -> Bool {
            date >= startDay && date < endDay
        }

        var events: [CashFlowEvent] = []

        // 1. 可用资金
        let liquidTypes: Set<AccountType> = [.cash, .debit, .ewallet, .prepaid]
        let startingBalance = accounts
            .filter {
                $0.deletedAt == nil
                    && !$0.isArchived
                    && $0.includeInNetWorth
                    && liquidTypes.contains($0.type)
            }
            .reduce(Int64(0)) { partial, account in
                partial + BalanceService.balance(
                    of: account,
                    transactions: liveTxns,
                    openingBalanceMinor: account.openingBalanceMinor
                )
            }

        // 2. 贷款还款
        let loanNames = Dictionary(uniqueKeysWithValues: loans.map { ($0.id, $0.name) })
        for item in loanScheduleItems where item.deletedAt == nil && !item.isPaid && inWindow(item.dueDate) {
            let name = loanNames[item.loanId] ?? "贷款"
            events.append(
                CashFlowEvent(
                    id: "loan-\(item.id.uuidString)",
                    date: item.dueDate,
                    title: "\(name) 第 \(item.periodIndex) 期",
                    kind: .loan,
                    amountMinor: -item.totalMinor
                )
            )
        }

        // 3. 信用卡：优先用已登记未结清账单，其次按账单周期消费估算
        let creditAccounts = accounts.filter {
            $0.deletedAt == nil && !$0.isArchived && $0.type.isCreditLike
        }
        for account in creditAccounts {
            let registered = statements
                .filter { $0.deletedAt == nil && !$0.isSettled && $0.accountId == account.id }
                .filter { statement in
                    let due = calendar.startOfDay(for: statement.dueDate)
                    return due >= startDay && due < endDay
                }
            for statement in registered {
                events.append(
                    CashFlowEvent(
                        id: "card-statement-\(statement.id.uuidString)",
                        date: statement.dueDate,
                        title: "\(account.displayName) 账单还款",
                        kind: .creditCard,
                        amountMinor: -statement.outstandingMinor
                    )
                )
            }
            if !registered.isEmpty { continue }

            guard let billDay = account.billDay, let dueDay = account.dueDay,
                  billDay > 0, dueDay > 0 else { continue }
            let cycle = CreditCardCycle(billDay: billDay, dueDay: dueDay)
            let balance = BalanceService.balance(
                of: account,
                transactions: liveTxns,
                openingBalanceMinor: account.openingBalanceMinor
            )
            let debt = balance < 0 ? -balance : 0
            guard debt > 0 else { continue }

            // 因为今天可能已经过了本月还款日，往后找 4 个月里第一个落在窗口内的还款日
            var seenDueDays: Set<Date> = []
            for offset in 0...3 {
                guard let reference = calendar.date(byAdding: .month, value: offset, to: startDate) else { continue }
                guard let due = cycle.dueDate(reference: reference) else { continue }
                let dueDayStart = calendar.startOfDay(for: due)
                guard inWindow(dueDayStart), !seenDueDays.contains(dueDayStart) else { continue }
                seenDueDays.insert(dueDayStart)
                guard let estimate = estimatedBillMinor(account: account, cycle: cycle, txns: liveTxns, reference: dueDayStart) else { continue }
                let amount = min(estimate, debt)
                guard amount > 0 else { continue }
                events.append(
                    CashFlowEvent(
                        id: "card-estimate-\(account.id.uuidString)-\(Int(dueDayStart.timeIntervalSince1970))",
                        date: dueDayStart,
                        title: "\(account.displayName) 还款（估算）",
                        kind: .creditCard,
                        amountMinor: -amount
                    )
                )
                // 一笔债务只计划一次还款，避免 60/90 天窗口里重复计
                break
            }
        }

        // 4. 周期记账
        for rule in recurringRules where rule.deletedAt == nil && !rule.isPaused {
            switch rule.templateType {
            case .expense:
                for date in projectedDates(rule: rule, startDay: startDay, endDay: endDay, calendar: calendar) {
                    events.append(
                        CashFlowEvent(
                            id: "recurring-\(rule.id.uuidString)-\(Int(date.timeIntervalSince1970))",
                            date: date,
                            title: rule.title,
                            kind: .recurring,
                            amountMinor: -rule.amountMinor
                        )
                    )
                }
            case .income:
                for date in projectedDates(rule: rule, startDay: startDay, endDay: endDay, calendar: calendar) {
                    events.append(
                        CashFlowEvent(
                            id: "recurring-\(rule.id.uuidString)-\(Int(date.timeIntervalSince1970))",
                            date: date,
                            title: rule.title,
                            kind: .recurring,
                            amountMinor: rule.amountMinor
                        )
                    )
                }
            default:
                continue
            }
        }

        // 5. 借入借出（有到期日的）
        for debt in debts where debt.deletedAt == nil && !debt.isSettled {
            guard let due = debt.dueDate, inWindow(due) else { continue }
            let amount: Int64 = debt.direction == .lend ? debt.amountMinor : -debt.amountMinor
            events.append(
                CashFlowEvent(
                    id: "debt-\(debt.id.uuidString)",
                    date: due,
                    title: debt.direction == .lend ? "收回借款 · \(debt.counterparty)" : "归还借款 · \(debt.counterparty)",
                    kind: debt.direction == .lend ? .receivable : .payable,
                    amountMinor: amount
                )
            )
        }

        events.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.title < rhs.title
        }

        return CashFlowPlan(
            startDate: startDay,
            endDate: endDay,
            startingBalanceMinor: startingBalance,
            events: events
        )
    }

    /// 按最近一个完整账单周期的消费估算本期待还
    private static func estimatedBillMinor(
        account: Account,
        cycle: CreditCardCycle,
        txns: [Txn],
        reference: Date
    ) -> Int64? {
        guard let period = cycle.statementPeriod(reference: reference) else { return nil }
        var expense: Int64 = 0
        var refund: Int64 = 0
        for txn in txns where txn.accountId == account.id && period.contains(txn.occurredAt) {
            if txn.type == .expense {
                expense += txn.amountMinor
            } else if RefundService.isRefund(txn) {
                refund += txn.amountMinor
            }
        }
        let bill = RefundService.netExpense(expenseMinor: expense, refundMinor: refund)
        return bill > 0 ? bill : nil
    }

    /// 周期规则在窗口内的发生日期（最多 90 次，避免异常规则）
    private static func projectedDates(
        rule: RecurringRule,
        startDay: Date,
        endDay: Date,
        calendar: Calendar
    ) -> [Date] {
        var cursor = rule.nextDate
        var result: [Date] = []
        var guardCount = 0

        while guardCount < 500 {
            guardCount += 1
            guard let next = RecurringEngine.nextDate(
                after: cursor,
                frequency: rule.frequency,
                interval: rule.interval,
                calendar: calendar
            ) else {
                break
            }
            if cursor >= endDay { break }
            if cursor >= startDay {
                result.append(cursor)
                if result.count >= 90 { break }
            }
            cursor = next
        }
        return result
    }
}
