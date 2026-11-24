import Foundation

/// 信用卡账期计算。
/// 规则：账单日 `billDay` 出账，最后还款日 `dueDay`；
/// 若 `dueDay <= billDay`，还款日属于次月。
struct CreditCardCycle {
    let billDay: Int
    let dueDay: Int

    /// 最近一次出账日（今天或之前）
    func latestBillDate(reference: Date, calendar: Calendar = AppCalendar.gregorian) -> Date? {
        guard billDay >= 1 else { return nil }
        let start = calendar.startOfDay(for: reference)
        let comps = calendar.dateComponents([.year, .month], from: start)

        if let thisMonth = date(year: comps.year, month: comps.month, day: billDay, calendar: calendar),
           thisMonth <= start {
            return thisMonth
        }
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: start) else { return nil }
        let prevComps = calendar.dateComponents([.year, .month], from: previousMonth)
        return date(year: prevComps.year, month: prevComps.month, day: billDay, calendar: calendar)
    }

    /// 当前账单周期的起止（含首尾）
    func statementPeriod(reference: Date, calendar: Calendar = AppCalendar.gregorian) -> DateInterval? {
        guard let bill = latestBillDate(reference: reference, calendar: calendar) else { return nil }
        let startOfBill = calendar.startOfDay(for: bill)
        guard let previousBill = calendar.date(byAdding: .month, value: -1, to: startOfBill),
              let periodStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: previousBill)) else {
            return nil
        }
        guard let periodEnd = calendar.date(byAdding: .day, value: 1, to: startOfBill) else { return nil }
        return DateInterval(start: periodStart, end: periodEnd)
    }

    /// 当前账单对应的最后还款日
    func dueDate(reference: Date, calendar: Calendar = AppCalendar.gregorian) -> Date? {
        guard let bill = latestBillDate(reference: reference, calendar: calendar), dueDay >= 1 else { return nil }
        let comps = calendar.dateComponents([.year, .month], from: bill)
        let sameMonth = dueDay > billDay
        let baseMonth = sameMonth ? bill : (calendar.date(byAdding: .month, value: 1, to: bill) ?? bill)
        let baseComps = calendar.dateComponents([.year, .month], from: baseMonth)
        return date(year: baseComps.year, month: baseComps.month, day: dueDay, calendar: calendar)
    }

    func daysUntilDue(reference: Date, calendar: Calendar = AppCalendar.gregorian) -> Int? {
        guard let due = dueDate(reference: reference, calendar: calendar) else { return nil }
        let from = calendar.startOfDay(for: reference)
        return calendar.dateComponents([.day], from: from, to: due).day
    }

    private func date(year: Int?, month: Int?, day: Int, calendar: Calendar) -> Date? {
        guard let year, let month else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let firstOfMonth = calendar.date(from: comps) else { return nil }
        let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        let clamped = min(day, range?.count ?? day)
        comps.day = clamped
        return calendar.date(from: comps)
    }
}
