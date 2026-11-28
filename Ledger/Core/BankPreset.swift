import SwiftUI
import UIKit

// MARK: - 素材来源
// 银行与支付渠道图标来自 Cookie 记账 App 资源包（用户自行提取，仅个人自用）。
// ⚠️ 这些是第三方商标素材，上架 App Store 前必须替换为自有或已授权素材。
// 详见 Ledger/Resources/ASSETS_SOURCE.md。

/// 银行 / 平台预设。
/// 有内置图标时显示图标，否则退回「品牌色 + 单字缩写」。
struct BankPreset: Identifiable, Hashable {
    let id: String
    let name: String
    /// 缩写，1–2 个汉字
    let short: String
    let colorHex: String
    /// 品牌色很浅时需要深色文字
    let darkText: Bool
    /// 选中后推荐的账户类型
    let suggestedType: AccountType

    static let all: [BankPreset] = [
        // 银行
        BankPreset(id: "cmb", name: "招商银行", short: "招", colorHex: "C7000B", darkText: false, suggestedType: .debit),
        BankPreset(id: "icbc", name: "工商银行", short: "工", colorHex: "E60012", darkText: false, suggestedType: .debit),
        BankPreset(id: "ccb", name: "建设银行", short: "建", colorHex: "0066B3", darkText: false, suggestedType: .debit),
        BankPreset(id: "abc", name: "农业银行", short: "农", colorHex: "009944", darkText: false, suggestedType: .debit),
        BankPreset(id: "boc", name: "中国银行", short: "中", colorHex: "B01F24", darkText: false, suggestedType: .debit),
        BankPreset(id: "bocom", name: "交通银行", short: "交", colorHex: "004A8F", darkText: false, suggestedType: .debit),
        BankPreset(id: "psbc", name: "邮储银行", short: "邮", colorHex: "007A33", darkText: false, suggestedType: .debit),
        BankPreset(id: "citic", name: "中信银行", short: "信", colorHex: "D80C24", darkText: false, suggestedType: .credit),
        BankPreset(id: "spdb", name: "浦发银行", short: "浦", colorHex: "005BAC", darkText: false, suggestedType: .debit),
        BankPreset(id: "cmbc", name: "民生银行", short: "民", colorHex: "009DD9", darkText: false, suggestedType: .debit),
        BankPreset(id: "cib", name: "兴业银行", short: "兴", colorHex: "0057A8", darkText: false, suggestedType: .debit),
        BankPreset(id: "ceb", name: "光大银行", short: "光", colorHex: "7A2E8E", darkText: false, suggestedType: .debit),
        BankPreset(id: "hxb", name: "华夏银行", short: "华", colorHex: "C8102E", darkText: false, suggestedType: .debit),
        BankPreset(id: "cgb", name: "广发银行", short: "广", colorHex: "E60012", darkText: false, suggestedType: .debit),
        BankPreset(id: "pab", name: "平安银行", short: "平", colorHex: "F26F21", darkText: false, suggestedType: .debit),
        BankPreset(id: "bosh", name: "上海银行", short: "沪", colorHex: "005BAC", darkText: false, suggestedType: .debit),
        BankPreset(id: "bob", name: "北京银行", short: "京", colorHex: "C8102E", darkText: false, suggestedType: .debit),
        BankPreset(id: "nbcb", name: "宁波银行", short: "宁", colorHex: "00A0E9", darkText: false, suggestedType: .debit),
        BankPreset(id: "webank", name: "微众银行", short: "微", colorHex: "1677FF", darkText: false, suggestedType: .debit),
        BankPreset(id: "mybank", name: "网商银行", short: "网", colorHex: "1677FF", darkText: false, suggestedType: .debit),

        // 平台
        BankPreset(id: "alipay", name: "支付宝", short: "支", colorHex: "1677FF", darkText: false, suggestedType: .ewallet),
        BankPreset(id: "wechat", name: "微信", short: "微", colorHex: "07C160", darkText: false, suggestedType: .ewallet),
        BankPreset(id: "qq", name: "QQ 钱包", short: "Q", colorHex: "12B7F5", darkText: false, suggestedType: .ewallet),
        BankPreset(id: "yeb", name: "余额宝", short: "余", colorHex: "F5A623", darkText: false, suggestedType: .ewallet),
        BankPreset(id: "lqt", name: "零钱通", short: "零", colorHex: "F7B500", darkText: true, suggestedType: .ewallet),
        BankPreset(id: "szrmb", name: "数字人民币", short: "数", colorHex: "E60012", darkText: false, suggestedType: .ewallet),
        BankPreset(id: "unionpay", name: "云闪付", short: "云", colorHex: "E60012", darkText: false, suggestedType: .ewallet),
        BankPreset(id: "huabei", name: "花呗", short: "花", colorHex: "1677FF", darkText: false, suggestedType: .bnpl),
        BankPreset(id: "jiebei", name: "借呗", short: "借", colorHex: "1677FF", darkText: false, suggestedType: .bnpl),
        BankPreset(id: "jdbt", name: "京东", short: "京", colorHex: "E1251B", darkText: false, suggestedType: .bnpl),
        BankPreset(id: "douyin", name: "抖音月付", short: "抖", colorHex: "FE2C55", darkText: false, suggestedType: .bnpl),
        BankPreset(id: "dywallet", name: "抖音钱包", short: "抖", colorHex: "000000", darkText: false, suggestedType: .ewallet),
        BankPreset(id: "meituan", name: "美团", short: "美", colorHex: "FFD100", darkText: true, suggestedType: .bnpl),
        BankPreset(id: "pdd", name: "拼多多", short: "拼", colorHex: "E02E24", darkText: false, suggestedType: .ewallet),
        BankPreset(id: "didi", name: "滴滴", short: "滴", colorHex: "FF7F41", darkText: false, suggestedType: .ewallet),
        BankPreset(id: "applepay", name: "Apple Pay", short: "", colorHex: "1C1C1E", darkText: false, suggestedType: .ewallet),

        // 兜底
        BankPreset(id: "cash", name: "现金", short: "现", colorHex: "34C759", darkText: false, suggestedType: .cash),
        BankPreset(id: "other", name: "其他", short: "其", colorHex: "8E8E93", darkText: false, suggestedType: .other)
    ]

    static func find(_ id: String?) -> BankPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// 根据名称反查（导入或旧数据用）
    static func match(name: String) -> BankPreset? {
        all.first { name.contains($0.name) }
    }
}

/// 品牌标记：优先用内置 Logo 图片，没有则退回「品牌色 + 缩写」，再退回中性类型图标。
struct BankMarkView: View {
    let bankId: String?
    let fallbackEmoji: String
    let fallbackColorHex: String
    /// 传入账户类型时，没有品牌 Logo 的账户改用单色类型图标（现金/储蓄卡/信用卡同一套观感）。
    var accountType: AccountType? = nil
    var size: CGFloat = 40

    private var preset: BankPreset? {
        BankPreset.find(bankId)
    }

    private var logoImage: UIImage? {
        guard let bankId else { return nil }
        return UIImage(named: "bank_\(bankId)")
    }

    var body: some View {
        Group {
            if let logoImage {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                    Image(uiImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.16)
                }
                .frame(width: size, height: size)
            } else if let preset {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(Color(hexString: preset.colorHex))
                    Text(preset.short)
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(preset.darkText ? Color.black : Color.white)
                }
                .frame(width: size, height: size)
            } else if let accountType {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                    Image(systemName: accountType.iconSymbol)
                        .font(.system(size: size * 0.40, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: size, height: size)
            } else {
                Text(fallbackEmoji)
                    .font(.system(size: size * 0.46))
                    .frame(width: size, height: size)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            }
        }
    }
}

/// 账户行统一使用的标记：品牌 Logo → 品牌缩写 → 单色类型图标。
struct AccountMarkView: View {
    let account: Account
    var size: CGFloat = 38

    var body: some View {
        BankMarkView(
            bankId: account.bankId,
            fallbackEmoji: account.iconEmoji,
            fallbackColorHex: account.colorHex,
            accountType: account.type,
            size: size
        )
    }
}
