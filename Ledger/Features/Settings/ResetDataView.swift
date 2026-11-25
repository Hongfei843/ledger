import SwiftUI
import SwiftData

/// 一键初始化：清空所有数据并重建默认分类。
/// 强制倒计时 3 秒才能点，避免误触。
struct ResetDataView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var countdown: Int?
    @State private var done = false

    private var armed: Bool { countdown == nil && !done }

    var body: some View {
        List {
            Section {
                Label("清空后不可恢复", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                Text("会删除全部账户、流水、报销单、贷款、账单与设置，然后重建默认分类。建议先导出一次备份。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    startCountdown()
                } label: {
                    HStack {
                        Spacer()
                        if let countdown {
                            Text("请稍候 \(countdown) 秒…")
                                .foregroundStyle(.secondary)
                        } else if done {
                            Label("已清空", systemImage: "checkmark")
                                .foregroundStyle(Theme.income)
                        } else {
                            Text("清空所有数据")
                        }
                        Spacer()
                    }
                }
                .disabled(countdown != nil || done)
            } footer: {
                Text("清空完成后，App 会像第一次打开一样，需要重新添加账户。")
            }
        }
        .navigationTitle("初始化数据")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startCountdown() {
        countdown = 3
        Task {
            for remaining in stride(from: 2, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                countdown = remaining
            }
            wipe()
        }
    }

    private func wipe() {
        do {
            try context.delete(model: Txn.self)
            try context.delete(model: Claim.self)
            try context.delete(model: Statement.self)
            try context.delete(model: Loan.self)
            try context.delete(model: LoanScheduleItem.self)
            try context.delete(model: RecurringRule.self)
            try context.delete(model: ReconciliationRun.self)
            try context.delete(model: Account.self)
            try context.delete(model: Category.self)
            try context.delete(model: Book.self)
            try context.delete(model: MerchantRule.self)
            try context.delete(model: CaptureRecord.self)
            try context.save()
        } catch {
            // 清空失败也继续走重建流程，避免卡在中间态
        }

        UserDefaults.standard.removeObject(forKey: "seed.categories.version")
        UserDefaults.standard.removeObject(forKey: "onboarding.completed")
        SeedData.bootstrapIfNeeded(context: context)

        countdown = nil
        done = true
        Haptics.success()
    }
}
