import SwiftUI
import SwiftData

/// 首次使用引导。非强制：每一步都能跳过，跳过也不会再弹。
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]
    @Query private var accounts: [Account]

    @AppStorage("onboarding.completed") private var completed = false

    @State private var step = 0
    @State private var selectedPresets: Set<String> = ["现金", "储蓄卡", "信用卡"]
    @State private var billDay = 5
    @State private var dueDay = 25
    @State private var didCreate = false
    @State private var showAddAccount = false

    private struct Preset: Identifiable {
        let id: String
        let name: String
        let emoji: String
        let type: AccountType
        let bankId: String
    }

    private let presets: [Preset] = [
        Preset(id: "现金", name: "现金", emoji: "💵", type: .cash, bankId: "cash"),
        Preset(id: "储蓄卡", name: "储蓄卡", emoji: "🏦", type: .debit, bankId: "other"),
        Preset(id: "信用卡", name: "信用卡", emoji: "💳", type: .credit, bankId: "other"),
        Preset(id: "微信", name: "微信钱包", emoji: "💬", type: .ewallet, bankId: "wechat"),
        Preset(id: "支付宝", name: "支付宝余额", emoji: "🅰️", type: .ewallet, bankId: "alipay"),
        Preset(id: "花呗", name: "花呗", emoji: "🌸", type: .bnpl, bankId: "huabei")
    ]

    private var creditAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && $0.type.isCreditLike }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 5)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.s)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        switch step {
                        case 0: welcome
                        case 1: accountPicker
                        case 2: accountSetup
                        case 3: creditSettings
                        default: finish
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }

                bottomBar
            }
            .background(Theme.pageBackground)
            .navigationTitle("开始使用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳过") { finishOnboarding() }
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showAddAccount) {
                AccountEditView(account: nil)
            }
        }
    }

    // MARK: - 步骤

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("一分钟把账本搭起来")
                .font(.title2.weight(.semibold))
            Text("记账最难的不是记，是「账对不上」。先把账户和余额设对，后面才省心。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                bullet("1", "选几个常用账户")
                bullet("2", "给信用卡设账单日与还款日")
                bullet("3", "之后每月提醒你对一次余额")
            }
            .padding(.top, Theme.Spacing.s)

            Text("所有数据只存在这台手机上，随时可以导出备份。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, Theme.Spacing.s)
        }
    }

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("你平时用哪些账户？")
                .font(.title3.weight(.semibold))
            Text("勾选后自动创建，之后可以随时改名或删除。")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.s) {
                ForEach(presets) { preset in
                    presetCell(preset)
                }
            }
        }
    }

    private var accountSetup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("补一下余额")
                .font(.title3.weight(.semibold))
            Text("现在填好，之后记账余额才准。账户名也可以在这里改。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(setupAccounts, id: \.id) { account in
                VStack(spacing: 8) {
                    HStack(spacing: Theme.Spacing.s) {
                        BankMarkView(
                            bankId: account.bankId,
                            fallbackEmoji: account.iconEmoji,
                            fallbackColorHex: account.colorHex,
                            size: 28
                        )
                        TextField("账户名", text: nameBinding(account))
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("期初余额")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: balanceBinding(account))
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(Theme.Spacing.m)
                .cardStyle(radius: 12)
            }

            Button {
                showAddAccount = true
            } label: {
                Label("添加其他账户", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        }
    }

    private var setupAccounts: [Account] {
        accounts
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func nameBinding(_ account: Account) -> Binding<String> {
        Binding(
            get: { account.name },
            set: { value in
                account.name = value
                account.updatedAt = Date()
                try? context.save()
            }
        )
    }

    private func balanceBinding(_ account: Account) -> Binding<String> {
        Binding(
            get: { Money.rawText(account.openingBalanceMinor) },
            set: { text in
                guard let value = Money.parse(text) else { return }
                account.openingBalanceMinor = value
                account.cachedBalanceMinor = value
                account.updatedAt = Date()
                try? context.save()
            }
        )
    }

    private var creditSettings: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("信用卡账单周期")
                .font(.title3.weight(.semibold))
            Text(creditAccounts.isEmpty ? "你还没有信用卡账户，这一步可以跳过。" : "设置后会自动计算本期账单与还款日，并在到期前提醒你。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !creditAccounts.isEmpty {
                VStack(spacing: Theme.Spacing.s) {
                    Stepper("账单日：每月 \(billDay) 日", value: $billDay, in: 1...28)
                    Stepper("还款日：每月 \(dueDay) 日", value: $dueDay, in: 1...28)
                }
                .padding(Theme.Spacing.m)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            }
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("准备好了")
                .font(.title2.weight(.semibold))
            Text("建议下一步：在「我的 → 对账」里填一次各账户的实际余额，把账面拉平。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("之后每月 1 号会提醒你对账；账户超过 30 天没对账，首页会有提示。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func bullet(_ index: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(index)
                .font(.caption2.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Theme.accent.opacity(0.15), in: Circle())
                .foregroundStyle(Theme.accent)
            Text(text).font(.subheadline)
        }
    }

    private func presetCell(_ preset: Preset) -> some View {
        let selected = selectedPresets.contains(preset.id)
        return Button {
            if selected {
                selectedPresets.remove(preset.id)
            } else {
                selectedPresets.insert(preset.id)
            }
            Haptics.selection()
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Text(preset.emoji).font(.system(size: 20))
                Text(preset.name).font(.subheadline)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.accent : .secondary)
            }
            .padding(Theme.Spacing.m)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.m) {
            if step > 0 {
                Button("上一步") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Button {
                advance()
            } label: {
                Text(step == 4 ? "开始记账" : "下一步")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(Theme.Spacing.xl)
        .background(.regularMaterial)
    }

    private func advance() {
        if step == 1 {
            createAccounts()
        }
        if step == 4 {
            finishOnboarding()
            return
        }
        step += 1
    }

    private func createAccounts() {
        guard !didCreate else { return }
        didCreate = true
        guard let bookId = books.first?.id else { return }

        let existingNames = Set(accounts.filter { $0.deletedAt == nil }.map { $0.name })
        var order = accounts.count

        for preset in presets where selectedPresets.contains(preset.id) && !existingNames.contains(preset.name) {
            let account = Account(
                bookId: bookId,
                name: preset.name,
                type: preset.type,
                iconEmoji: preset.emoji,
                sortOrder: order
            )
            account.bankId = preset.bankId
            context.insert(account)
            order += 1
        }
        try? context.save()
    }

    private func finishOnboarding() {
        for account in creditAccounts {
            account.billDay = billDay
            account.dueDay = dueDay
            account.updatedAt = Date()
        }
        try? context.save()
        completed = true
        dismiss()
    }
}
