import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Query private var txns: [Txn]
    @Query private var accounts: [Account]
    @Query private var loans: [Loan]
    @Query private var scheduleItems: [LoanScheduleItem]
    @AppStorage(CategoryIcon.styleKey) private var iconStyle: String = IconStyle.symbol.rawValue
    @AppStorage(Theme.accentHexKey) private var accentHex: String = Theme.defaultAccentHex
    @AppStorage(NotificationService.enabledKey) private var remindersEnabled = false
    @AppStorage("security.lockEnabled") private var lockEnabled = false
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
                Section {
                    HStack(spacing: Theme.Spacing.l) {
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                            .shadow(color: Theme.accent.opacity(0.20), radius: 12, y: 5)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("轻账")
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                            Text("把每一笔记成确定性")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("本机私密", systemImage: "lock.shield")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.10), in: Capsule())
                    }
                    .padding(.vertical, Theme.Spacing.s)
                    .listRowBackground(Color.clear)
                }

                Section("记账") {
                    settingsLink("账本管理", systemImage: "books.vertical") { BookManageView() }
                    settingsLink("分类管理", systemImage: "square.grid.2x2") { CategoryManageView() }
                    settingsLink("常用组合", systemImage: "bolt") { QuickTemplateListView() }
                    settingsLink("周期记账", systemImage: "repeat") { RecurringListView() }
                    settingsLink("截图记账", systemImage: "text.viewfinder") { ScreenshotGuideView() }
                    settingsLink("导入账单", systemImage: "square.and.arrow.down") { ImportView() }
                    settingsLink("账单比对", systemImage: "checklist") { BillCompareView() }
                }

                Section("资产") {
                    settingsLink("账户管理", systemImage: "creditcard") { AccountsView() }
                    settingsLink("资产总览", systemImage: "chart.line.uptrend.xyaxis") { AssetOverviewView() }
                    settingsLink("资金计划", systemImage: "calendar") { CashFlowPlanView() }
                    settingsLink("对账", systemImage: "checkmark.circle") { ReconciliationView() }
                    settingsLink("借入借出", systemImage: "arrow.left.arrow.right") { DebtListView() }
                }

                Section("数据") {
                    HStack(spacing: Theme.Spacing.xl) {
                        settingsMetric(title: "有效流水", value: "\(liveTxns.count)", unit: "笔")
                        settingsMetric(title: "当前账户", value: "\(accounts.filter { $0.deletedAt == nil }.count)", unit: "个")
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    settingsLink("数据健康", systemImage: "heart.text.square") { DataHealthView() }
                    settingsLink("导出分析包", systemImage: "square.and.arrow.up") { ExportView() }
                    settingsLink("备份与恢复", systemImage: "externaldrive") { BackupRestoreView() }
                }

                Section("维护") {
                    settingsLink("初始化数据", systemImage: "arrow.counterclockwise") { ResetDataView() }
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

                Section("关于") {
                    LabeledContent("版本", value: appVersionText)
                    LabeledContent("数据存储", value: "仅本机，不上传")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground)
            .listSectionSpacing(18)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func settingsLink<Destination: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: Theme.Spacing.m) {
                LedgerIconBadge(systemImage: systemImage, size: 34)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.vertical, 3)
        }
    }

    private func settingsMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Fonts.amountL)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
