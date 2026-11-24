import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([
        Book.self,
        Account.self,
        Category.self,
        Txn.self,
        Claim.self,
        Loan.self,
        LoanScheduleItem.self,
        Statement.self,
        MerchantRule.self,
        CaptureRecord.self,
        RecurringRule.self
    ])

    /// 创建容器。失败时返回 nil，由界面展示可读的错误页，避免白屏或崩溃。
    static func make(inMemory: Bool = false) -> ModelContainer? {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            print("[Ledger] ModelContainer 初始化失败: \(error)")
            return nil
        }
    }

    /// 预览与测试用的内存容器
    static func preview() -> ModelContainer {
        if let container = make(inMemory: true) {
            return container
        }
        // 预览兜底：正常不会走到这里
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}
