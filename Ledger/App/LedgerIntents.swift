import AppIntents
import Foundation
import SwiftData

extension Notification.Name {
    static let intentOpenEntry = Notification.Name("ledger.intent.openEntry")
    static let intentImportScreenshot = Notification.Name("ledger.intent.importScreenshot")
}

enum IntentAction: String {
    case entry
    case screenshot
}

/// App Intent 与 App UI 之间的桥：通知 + UserDefaults 兜底（冷启动时通知可能来不及被接收）
enum IntentBridge {
    static let pendingKey = "intent.pendingAction"

    static func request(_ action: IntentAction) {
        UserDefaults.standard.set(action.rawValue, forKey: pendingKey)
        switch action {
        case .entry:
            NotificationCenter.default.post(name: .intentOpenEntry, object: nil)
        case .screenshot:
            NotificationCenter.default.post(name: .intentImportScreenshot, object: nil)
        }
    }

    static func takePending() -> IntentAction? {
        guard let raw = UserDefaults.standard.string(forKey: pendingKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return IntentAction(rawValue: raw)
    }

    static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }
}

// MARK: - 打开记账

struct OpenEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔"
    static var description = IntentDescription("打开轻账的记账面板，记一笔支出或收入。")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.request(.entry)
        return .result()
    }
}

// MARK: - 截图记账

struct ScreenshotImportIntent: AppIntent {
    static var title: LocalizedStringResource = "截图记账"
    static var description = IntentDescription("把「轻账」文件夹里最新一张截图识别成记账草稿。")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.request(.screenshot)
        return .result()
    }
}

// MARK: - 本月支出（不打开 App，直接播报）

struct MonthlySpendingIntent: AppIntent {
    static var title: LocalizedStringResource = "本月支出"
    static var description = IntentDescription("播报本月支出、收入和结余，不用打开 App。")
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = ModelContainerFactory.make() else {
            return .result(dialog: "轻账的数据还没准备好。")
        }
        let context = ModelContext(container)
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let currentBookId = BookScope.currentId ?? books.first(where: { $0.isDefault })?.id ?? books.first?.id
        let txns = ((try? context.fetch(FetchDescriptor<Txn>())) ?? []).filter {
            $0.deletedAt == nil && (currentBookId == nil || $0.bookId == currentBookId)
        }
        let claims = (try? context.fetch(FetchDescriptor<Claim>())) ?? []
        let summary = StatsEngine.summary(
            range: AppCalendar.monthInterval(containing: Date()),
            caliber: .cashFlow,
            txns: txns,
            claims: claims
        )
        let text = "本月支出 \(Money.formatPlain(summary.expenseMinor)) 元，收入 \(Money.formatPlain(summary.incomeMinor)) 元，结余 \(Money.formatPlain(summary.balanceMinor)) 元。"
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - 快捷指令/Spotlight 自动注册

struct LedgerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenEntryIntent(),
            phrases: [
                "用\(.applicationName)记一笔",
                "\(.applicationName)记账"
            ],
            shortTitle: "记一笔",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: ScreenshotImportIntent(),
            phrases: [
                "\(.applicationName)截图记账"
            ],
            shortTitle: "截图记账",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: MonthlySpendingIntent(),
            phrases: [
                "\(.applicationName)本月支出",
                "\(.applicationName)这个月花了多少"
            ],
            shortTitle: "本月支出",
            systemImageName: "chart.pie"
        )
    }
}
