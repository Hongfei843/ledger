import Foundation
import UserNotifications

/// 本地通知：还款提醒与对账提醒。
/// 全部本地调度，不联网、不推送。
enum NotificationService {
    static let enabledKey = "ui.reminders.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// 重排所有提醒：贷款剩余期次 + 信用卡还款日
    static func reschedule(loans: [Loan], items: [LoanScheduleItem], accounts: [Account]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard isEnabled else { return }

        // 贷款：接下来 3 期，提前 3 天与当天各提醒一次
        let upcoming = items
            .filter { $0.deletedAt == nil && !$0.isPaid && $0.dueDate > Date() }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(6)

        for item in upcoming {
            guard let loan = loans.first(where: { $0.id == item.loanId }) else { continue }
            schedule(
                title: "还款提醒：\(loan.name)",
                body: "本期应还 \(Money.format(item.totalMinor))，其中本金 \(Money.format(item.principalMinor))、利息 \(Money.format(item.interestMinor))",
                date: item.dueDate,
                identifier: "loan-\(item.id.uuidString)",
                daysBefore: [3, 0]
            )
        }

        // 信用卡：还款日前 3 天与当天
        for account in accounts where account.deletedAt == nil && account.type.isCreditLike {
            guard let billDay = account.billDay, let dueDay = account.dueDay, billDay > 0, dueDay > 0 else { continue }
            let cycle = CreditCardCycle(billDay: billDay, dueDay: dueDay)
            guard let due = cycle.dueDate(reference: Date()) else { continue }
            schedule(
                title: "信用卡还款：\(account.name)",
                body: "最后还款日 \(DateFormatter.ledgerShort.string(from: due))，请核对账单金额",
                date: due,
                identifier: "card-\(account.id.uuidString)",
                daysBefore: [3, 0]
            )
        }

        scheduleMonthlyReconciliation()
        scheduleBillIssuedReminders(accounts: accounts)
        scheduleBackupReminder()
    }

    /// 账单日次日提醒登记账单
    private static func scheduleBillIssuedReminders(accounts: [Account]) {
        let calendar = AppCalendar.gregorian
        for account in accounts where account.deletedAt == nil && account.type.isCreditLike {
            guard let billDay = account.billDay, billDay >= 1 else { continue }
            let cycle = CreditCardCycle(billDay: billDay, dueDay: account.dueDay ?? 20)
            guard let bill = cycle.latestBillDate(reference: Date()) else { continue }

            var fire = calendar.date(byAdding: .day, value: 1, to: bill) ?? bill
            if fire <= Date() {
                fire = calendar.date(byAdding: .month, value: 1, to: fire) ?? fire
            }

            let content = UNMutableNotificationContent()
            content.title = "账单已出：\(account.name)"
            content.body = "记得登记本期账单金额，再核对一下 App 算的对不对。"
            content.sound = .default

            var comps = calendar.dateComponents([.year, .month, .day], from: fire)
            comps.hour = 9
            comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "bill-\(account.id.uuidString)", content: content, trigger: trigger)
            )
        }
    }

    /// 每周日晚提醒导出备份
    private static func scheduleBackupReminder() {
        var comps = DateComponents()
        comps.weekday = 1 // 周日
        comps.hour = 20
        comps.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "该备份了"
        content.body = "数据只在这台手机上，我的 → 备份与恢复，存一份到文件 App。"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "backup-weekly", content: content, trigger: trigger)
        )
    }

    /// 每月 1 号 20:00 提醒对账（重复触发）
    private static func scheduleMonthlyReconciliation() {
        var comps = DateComponents()
        comps.day = 1
        comps.hour = 20
        comps.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "该对账了"
        content.body = "花两分钟核对各账户余额，账才不会越记越偏。"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "reconcile-monthly", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func schedule(
        title: String,
        body: String,
        date: Date,
        identifier: String,
        daysBefore: [Int]
    ) {
        let calendar = AppCalendar.gregorian
        for offset in daysBefore {
            guard let fireDate = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: fireDate)
            comps.hour = 9
            comps.minute = 0
            guard let fire = calendar.date(from: comps), fire > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "\(identifier)-\(offset)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
