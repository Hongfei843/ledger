import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Query private var txns: [Txn]
    @Query private var accounts: [Account]
    @Query private var loans: [Loan]
    @Query private var scheduleItems: [LoanScheduleItem]
    @AppStorage(CategoryIcon.styleKey) private var iconStyle: String = IconStyle.emoji.rawValue
    @AppStorage(Theme.accentHexKey) private var accentHex: String = Theme.defaultAccentHex
    @AppStorage(NotificationService.enabledKey) private var remindersEnabled = false
    @AppStorage("security.lockEnabled") private var lockEnabled = false
    @State private var currentIconName: String? = UIApplication.shared.alternateIconName
    @State private var iconMessage: String?

    private struct AppIconOption: Identifiable {
        let id: String?
        let title: String
        let preview: String
    }

    private let iconOptions: [AppIconOption] = [
        AppIconOption(id: nil, title: "默认", preview: "iconPreview_default"),
        AppIconOption(id: "AppIconMinimal", title: "极简", preview: "iconPreview_minimal"),
        AppIconOption(id: "AppIconCoin", title: "金币", preview: "iconPreview_coin"),
        AppIconOption(id: "AppIconChart", title: "图表", preview: "iconPreview_chart")
    ]

    private var liveTxns: [Txn] {
        txns.filter { $0.deletedAt == nil }
    }

    /// 从 Info.plist 读取真实版本，避免写死
    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("数据") {
                    NavigationLink("账户管理") {
                        AccountsView()
                    }
                    NavigationLink("分类管理") {
                        CategoryManageView()
                    }
                    NavigationLink("对账") {
                        ReconciliationView()
                    }
                    NavigationLink("资产总览") {
                        AssetOverviewView()
                    }
                    NavigationLink("资金计划") {
                        CashFlowPlanView()
                    }
                    NavigationLink("周期记账") {
                        RecurringListView()
                    }
                    NavigationLink("常用组合") {
                        QuickTemplateListView()
                    }
                    NavigationLink("借入借出") {
                        DebtListView()
                    }
                    NavigationLink("数据健康") {
                        DataHealthView()
                    }
                    NavigationLink("导入账单") {
                        ImportView()
                    }
                    NavigationLink("账单比对") {
                        BillCompareView()
                    }
                    NavigationLink("截图记账") {
                        ScreenshotGuideView()
                    }
                    NavigationLink("导出分析包") {
                        ExportView()
                    }
                    LabeledContent("流水条数", value: "\(liveTxns.count)")
                    LabeledContent("账户数", value: "\(accounts.filter { $0.deletedAt == nil }.count)")
                }

                Section("维护") {
                    NavigationLink("初始化数据") {
                        ResetDataView()
                    }
                }

                Section("外观") {
                    Picker("分类图标", selection: $iconStyle) {
                        ForEach(IconStyle.allCases) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    HStack {
                        Text("主题色")
                        Spacer()
                        HStack(spacing: 10) {
                            ForEach(Theme.presets) { preset in
                                themeDot(preset)
                            }
                        }
                    }
                }

                Section {
                    Toggle("还款提醒", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) { _, enabled in
                            Task {
                                if enabled {
                                    let granted = await NotificationService.requestAuthorization()
                                    if !granted {
                                        remindersEnabled = false
                                        return
                                    }
                                }
                                NotificationService.reschedule(
                                    loans: loans,
                                    items: scheduleItems,
                                    accounts: accounts
                                )
                            }
                        }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("包含：贷款到期前 3 天与当天、信用卡还款日前 3 天与当天、账单日次日提醒登记账单、每月 1 号对账提醒、每周日备份提醒。全部本地通知，不联网。")
                }

                Section {
                    Toggle("面容 ID / 密码锁", isOn: $lockEnabled)
                        .onChange(of: lockEnabled) { _, enabled in
                            guard enabled else { return }
                            Task {
                                let ok = await BiometricLock.authenticate(reason: "开启应用锁")
                                if !ok {
                                    await MainActor.run { lockEnabled = false }
                                }
                            }
                        }
                } header: {
                    Text("安全")
                } footer: {
                    Text("开启后，每次从后台回到轻账都需要验证。数据本身仍只存在本机。")
                }

                Section("应用图标") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.l) {
                            ForEach(iconOptions) { option in
                                iconCell(option)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersionText)
                }
            }
            .navigationTitle("我的")
            .alert(
                "应用图标",
                isPresented: Binding(
                    get: { iconMessage != nil },
                    set: { if !$0 { iconMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(iconMessage ?? "")
            }
        }
    }

    private func iconCell(_ option: AppIconOption) -> some View {
        let selected = currentIconName == option.id
        return Button {
            applyIcon(option.id)
        } label: {
            VStack(spacing: 6) {
                Image(option.preview)
                    .resizable()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2)
                    )
                Text(option.title)
                    .font(.caption2)
                    .foregroundStyle(selected ? Theme.accent : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func applyIcon(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            iconMessage = "这台设备或这套安装方式不支持切换备用图标。"
            return
        }
        UIApplication.shared.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
                if let error {
                    iconMessage = "切换图标失败：\(error.localizedDescription)"
                    Haptics.warning()
                } else {
                    currentIconName = name
                    iconMessage = name == nil ? "已切回默认图标。" : "已切换图标，回到桌面查看（系统可能延迟几秒）。"
                    Haptics.success()
                }
            }
        }
    }

    private func themeDot(_ preset: Theme.Preset) -> some View {
        let hex = String(format: "%06X", preset.hex)
        let selected = accentHex.uppercased() == hex
        return Button {
            accentHex = hex
            Haptics.selection()
        } label: {
            Circle()
                .fill(Color(hex: preset.hex))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle().stroke(Color.primary.opacity(selected ? 0.55 : 0), lineWidth: 2)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(selected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
    }
}
