import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var txns: [Txn]
    @Query private var accounts: [Account]
    @AppStorage(CategoryIcon.styleKey) private var iconStyle: String = IconStyle.emoji.rawValue

    private var liveTxns: [Txn] {
        txns.filter { $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("数据") {
                    NavigationLink("账户管理") {
                        AccountsView()
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
                        HStack(spacing: 8) {
                            ForEach(Theme.presets) { preset in
                                Circle()
                                    .fill(Color(hex: preset.hex))
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("构建", value: "开发中")
                }
            }
            .navigationTitle("我的")
        }
    }
}
