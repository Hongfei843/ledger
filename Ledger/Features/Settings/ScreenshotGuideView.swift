import SwiftUI
import UIKit

/// 截图记账 / 快捷指令 / 操作按钮 的接入说明。
struct ScreenshotGuideView: View {
    var body: some View {
        List {
            Section {
                Text("截图里识别金额、商户和付款方式（银行/卡号后四位），打开「记一笔」并预填，核对后保存。OCR 全部在本机完成，图片不上传。")
                    .font(.callout)
            }

            Section {
                guideRow(1, "长按桌面「轻账」图标 → 直接选「截图记账」或「记一笔」")
                guideRow(2, "不需要进「快捷指令」App，也不用配置任何东西")
                Button {
                    openShortcutsApp()
                } label: {
                    Label("打开「快捷指令」App", systemImage: "square.stack.3d.up")
                }
            } header: {
                Text("最快的方式（零配置）")
            } footer: {
                Text("系统不允许 App 替你自动创建快捷指令；想用操作按钮/控制中心/锁屏触发时，再按下面步骤建一次。App 已内置桌面快捷菜单，日常用长按图标就够了。")
            }

            Section {
                guideRow(1, "打开「快捷指令」→ 新建快捷指令")
                guideRow(2, "添加动作「截屏」")
                guideRow(3, "添加动作「存储文件」：保存位置选「我的 iPhone → 轻账」，关闭「询问保存位置」")
                guideRow(4, "添加动作「打开 URL」，填 ledger://import-screenshot")
                guideRow(5, "命名为「轻账截图记账」，然后到 设置 → 操作按钮 → 快捷指令 选它")
                guideRow(6, "在付款页、账单页按操作按钮，截图会自动被识别并打开预填的记账页")
            } header: {
                Text("推荐：快捷指令 + 操作按钮")
            } footer: {
                Text("也可以把这个快捷指令放进控制中心或锁屏，效果一样。")
            }

            Section("备用入口") {
                Text("• 在「文件」App 里点开截图 → 用轻账打开（已注册图片类型）\n• 截图存到「轻账」文件夹后，在「文件」App 中直接打开\n• App 内「明细」页右上角取景框：直接从相册选图识别")
                    .font(.callout)
            }

            Section("说明") {
                Text("• 截图导入只预填金额、商户和日期，不会自动保存\n• 一张截图只能导入一次，成功导入后会删除「轻账」目录里的原文件\n• 没识别出金额时会照常打开表单，手动补填即可")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("截图记账")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else { return }
        UIApplication.shared.open(url)
    }

    private func guideRow(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Text("\(index)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18)
                .background(Theme.accent.opacity(0.14), in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
