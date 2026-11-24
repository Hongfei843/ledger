import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var txns: [Txn]
    @Query private var accounts: [Account]
    @Query private var loans: [Loan]
    @Query private var scheduleItems: [LoanScheduleItem]
    @AppStorage(CategoryIcon.styleKey) private var iconStyle: String = IconStyle.emoji.rawValue
    @AppStorage(Theme.accentHexKey) private var accentHex: String = Theme.defaultAccentHex
    @AppStorage(NotificationService.enabledKey) private var remindersEnabled = false

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
                    NavigationLink("导入账单") {
                        ImportView()
                    }
                    NavigationLink("导出分析包") {
                        ExportView()
                    }
                    LabeledContent("流水条数", value: "\(liveTxns.count)")
                    LabeledContent("账户数", value: "\(accounts.filter { $0.deletedAt == nil }.count)")
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
                    Text("贷款到期前 3 天与当天、信用卡还款日前 3 天与当天各提醒一次。全部本地通知，不联网。")
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersionText)
                }
            }
            .navigationTitle("我的")
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
