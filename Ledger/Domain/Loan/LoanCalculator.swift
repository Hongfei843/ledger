import Foundation

struct ScheduledPayment: Equatable {
    let periodIndex: Int
    let dueDate: Date
    let principalMinor: Int64
    let interestMinor: Int64
    let feeMinor: Int64

    var totalMinor: Int64 {
        principalMinor + interestMinor + feeMinor
    }
}

enum PrepayStrategy: String, CaseIterable, Identifiable {
    case shortenTerm
    case reducePayment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shortenTerm: return "缩短期限"
        case .reducePayment: return "减少月供"
        }
    }
}

/// 摊销计算。全程 Decimal 高精度，最后四舍五入到「分」。
/// 不变式：Σ principal == 合同本金（尾差全部并入最后一期）。
enum LoanCalculator {
    // MARK: - 工具

    private static func roundMinor(_ value: Decimal) -> Int64 {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 0, .plain)
        return NSDecimalNumber(decimal: result).int64Value
    }

    private static func power(_ base: Decimal, _ exponent: Int) -> Decimal {
        var result = Decimal(1)
        for _ in 0..<max(0, exponent) {
            result *= base
        }
        return result
    }

    private static func monthlyRate(_ annualRateBp: Int) -> Decimal {
        Decimal(annualRateBp) / Decimal(10000) / Decimal(12)
    }

    // MARK: - 生成还款计划

    static func schedule(
        principalMinor: Int64,
        annualRateBp: Int,
        termMonths: Int,
        method: RepaymentMethod,
        firstDueDate: Date,
        calendar: Calendar = AppCalendar.gregorian
    ) -> [ScheduledPayment] {
        guard principalMinor > 0, termMonths > 0 else { return [] }
        let n = termMonths

        switch method {
        case .equalInstallment:
            return equalInstallment(principalMinor, annualRateBp, n, firstDueDate, calendar, asFee: false)
        case .installmentFee:
            return equalInstallment(principalMinor, annualRateBp, n, firstDueDate, calendar, asFee: true)
        case .equalPrincipal:
            return equalPrincipal(principalMinor, annualRateBp, n, firstDueDate, calendar)
        case .interestOnly:
            return interestOnly(principalMinor, annualRateBp, n, firstDueDate, calendar)
        case .bullet:
            return bullet(principalMinor, annualRateBp, n, firstDueDate, calendar)
        }
    }

    private static func equalInstallment(
        _ principal: Int64,
        _ annualRateBp: Int,
        _ n: Int,
        _ firstDueDate: Date,
        _ calendar: Calendar,
        asFee: Bool
    ) -> [ScheduledPayment] {
        let i = monthlyRate(annualRateBp)
        var items: [ScheduledPayment] = []
        var remaining = Decimal(principal)

        var payment = Decimal(0)
        if i == 0 {
            payment = Decimal(principal) / Decimal(n)
        } else {
            let factor = power(1 + i, n)
            payment = Decimal(principal) * i * factor / (factor - 1)
        }

        for period in 1...n {
            let dueDate = calendar.date(byAdding: .month, value: period - 1, to: firstDueDate) ?? firstDueDate
            let interestRaw = roundMinor(remaining * i)
            var principalPart: Int64

            if period == n {
                principalPart = roundMinor(remaining)
            } else {
                principalPart = roundMinor(payment) - interestRaw
                if principalPart < 0 { principalPart = 0 }
                let cap = roundMinor(remaining)
                if principalPart > cap { principalPart = cap }
            }

            remaining -= Decimal(principalPart)
            if remaining < 0 { remaining = 0 }

            items.append(
                ScheduledPayment(
                    periodIndex: period,
                    dueDate: dueDate,
                    principalMinor: principalPart,
                    interestMinor: asFee ? 0 : interestRaw,
                    feeMinor: asFee ? interestRaw : 0
                )
            )
        }
        return items
    }

    private static func equalPrincipal(
        _ principal: Int64,
        _ annualRateBp: Int,
        _ n: Int,
        _ firstDueDate: Date,
        _ calendar: Calendar
    ) -> [ScheduledPayment] {
        let i = monthlyRate(annualRateBp)
        var items: [ScheduledPayment] = []
        var remaining = Decimal(principal)
        let basePrincipal = roundMinor(Decimal(principal) / Decimal(n))

        for period in 1...n {
            let dueDate = calendar.date(byAdding: .month, value: period - 1, to: firstDueDate) ?? firstDueDate
            let interest = roundMinor(remaining * i)
            let principalPart = period == n ? roundMinor(remaining) : min(basePrincipal, roundMinor(remaining))
            remaining -= Decimal(principalPart)
            if remaining < 0 { remaining = 0 }
            items.append(
                ScheduledPayment(
                    periodIndex: period,
                    dueDate: dueDate,
                    principalMinor: principalPart,
                    interestMinor: interest,
                    feeMinor: 0
                )
            )
        }
        return items
    }

    private static func interestOnly(
        _ principal: Int64,
        _ annualRateBp: Int,
        _ n: Int,
        _ firstDueDate: Date,
        _ calendar: Calendar
    ) -> [ScheduledPayment] {
        let i = monthlyRate(annualRateBp)
        let interest = roundMinor(Decimal(principal) * i)
        var items: [ScheduledPayment] = []

        for period in 1...n {
            let dueDate = calendar.date(byAdding: .month, value: period - 1, to: firstDueDate) ?? firstDueDate
            items.append(
                ScheduledPayment(
                    periodIndex: period,
                    dueDate: dueDate,
                    principalMinor: period == n ? principal : 0,
                    interestMinor: interest,
                    feeMinor: 0
                )
            )
        }
        return items
    }

    private static func bullet(
        _ principal: Int64,
        _ annualRateBp: Int,
        _ n: Int,
        _ firstDueDate: Date,
        _ calendar: Calendar
    ) -> [ScheduledPayment] {
        let i = monthlyRate(annualRateBp)
        let totalInterest = roundMinor(Decimal(principal) * i * Decimal(n))
        let dueDate = calendar.date(byAdding: .month, value: n - 1, to: firstDueDate) ?? firstDueDate
        return [
            ScheduledPayment(
                periodIndex: 1,
                dueDate: dueDate,
                principalMinor: principal,
                interestMinor: totalInterest,
                feeMinor: 0
            )
        ]
    }

    // MARK: - 实际年化（IRR）

    /// 月度 IRR；年化 = (1+irr)^12 − 1
    static func monthlyIRR(principalMinor: Int64, payments: [Int64]) -> Double? {
        guard principalMinor > 0, !payments.isEmpty else { return nil }
        let initial = Double(principalMinor)
        let flows = payments.map { Double($0) }

        func npv(_ rate: Double) -> Double {
            var value = initial
            for (index, flow) in flows.enumerated() {
                value -= flow / pow(1 + rate, Double(index + 1))
            }
            return value
        }

        var low = -0.9
        var high = 1.0
        var fLow = npv(low)
        let fHigh = npv(high)
        guard fLow * fHigh < 0 else { return nil }

        for _ in 0..<120 {
            let mid = (low + high) / 2
            let fMid = npv(mid)
            if abs(fMid) < 0.0000001 { return mid }
            if fLow * fMid < 0 {
                high = mid
            } else {
                low = mid
                fLow = fMid
            }
        }
        return (low + high) / 2
    }

    static func annualizedRate(monthlyIRR: Double) -> Double {
        pow(1 + monthlyIRR, 12) - 1
    }

    /// 分期实际年化：给定本金、期数、每期还款
    static func effectiveAnnualRate(principalMinor: Int64, termMonths: Int, paymentMinor: Int64) -> Double? {
        guard termMonths > 0, paymentMinor > 0 else { return nil }
        let payments = Array(repeating: paymentMinor, count: termMonths)
        guard let monthly = monthlyIRR(principalMinor: principalMinor, payments: payments) else { return nil }
        return annualizedRate(monthlyIRR: monthly)
    }

    // MARK: - 汇总

    static func totalInterest(_ items: [ScheduledPayment]) -> Int64 {
        items.reduce(Int64(0)) { $0 + $1.interestMinor + $1.feeMinor }
    }

    static func savedInterest(original: [ScheduledPayment], updated: [ScheduledPayment]) -> Int64 {
        max(0, totalInterest(original) - totalInterest(updated))
    }

    /// 提前还款后重算剩余计划
    /// - shortenTerm：保持原月供，缩短期数
    /// - reducePayment：保持原剩余期数，降低月供
    static func reschedule(
        outstandingMinor: Int64,
        annualRateBp: Int,
        remainingMonths: Int,
        originalMonthlyPaymentMinor: Int64,
        method: RepaymentMethod,
        firstDueDate: Date,
        strategy: PrepayStrategy
    ) -> [ScheduledPayment] {
        guard outstandingMinor > 0, remainingMonths > 0 else { return [] }

        if strategy == .reducePayment {
            return schedule(
                principalMinor: outstandingMinor,
                annualRateBp: annualRateBp,
                termMonths: remainingMonths,
                method: method,
                firstDueDate: firstDueDate
            )
        }

        // 缩短期限：按期供不变反推期数
        let i = monthlyRate(annualRateBp)
        if originalMonthlyPaymentMinor <= 0 || i == 0 {
            return schedule(
                principalMinor: outstandingMinor,
                annualRateBp: annualRateBp,
                termMonths: max(1, remainingMonths / 2),
                method: method,
                firstDueDate: firstDueDate
            )
        }

        var months = remainingMonths
        let payment = originalMonthlyPaymentMinor
        for candidate in 1...remainingMonths {
            let trial = schedule(
                principalMinor: outstandingMinor,
                annualRateBp: annualRateBp,
                termMonths: candidate,
                method: method,
                firstDueDate: firstDueDate
            )
            guard let first = trial.first else { continue }
            if first.totalMinor <= payment {
                months = candidate
            }
        }
        months = max(1, months)

        return schedule(
            principalMinor: outstandingMinor,
            annualRateBp: annualRateBp,
            termMonths: months,
            method: method,
            firstDueDate: firstDueDate
        )
    }
}
