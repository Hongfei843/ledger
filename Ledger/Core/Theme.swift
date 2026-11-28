import SwiftUI
import UIKit

/// 视觉 token：颜色、间距、圆角。所有视图只能引用这里的值。
enum Theme {
    /// 强调色存储键（UserDefaults / AppStorage 共用）
    static let accentHexKey = "ui.accentHex"
    static let defaultAccentHex = "526B60"

    /// 当前强调色（跟随设置；深色模式下自动提亮，保证在深色背景上可读）
    static var accentHex: String {
        UserDefaults.standard.string(forKey: accentHexKey) ?? defaultAccentHex
    }

    static var accent: Color {
        let hex = accentHex
        return Color(uiColor: UIColor { traits in
            let base = UIColor(hexString: hex)
            return traits.userInterfaceStyle == .dark ? base.lightened(by: 0.28) : base
        })
    }

    // 语义色：明暗各一套，避免深色下过暗看不清
    static let income = Color(light: 0x1F8A5B, dark: 0x4CD38C)
    static let warning = Color(light: 0xC2410C, dark: 0xFF9E64)
    static let danger = Color(light: 0xDC2626, dark: 0xFF6B6B)
    static let transfer = Color.secondary

    // 瓷器浅色 / 墨玉深色：低饱和背景让金额和图表成为视觉主角
    static let pageBackground = Color(light: 0xF4F5F2, dark: 0x101312)
    static let cardBackground = Color(light: 0xFFFFFF, dark: 0x1B1E1D)
    static let subtleBackground = Color(light: 0xEBEEEA, dark: 0x252927)
    static let divider = Color(light: 0xE2E6E0, dark: 0x303532)

    static var heroGradient: LinearGradient {
        let base = UIColor(hexString: accentHex)
        return LinearGradient(
            colors: [Color(uiColor: base), Color(uiColor: base.darkened(by: 0.16))],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // 间距
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // 圆角
    enum Radius {
        static let card: CGFloat = 24
        static let button: CGFloat = 16
        static let sheet: CGFloat = 28
        static let icon: CGFloat = 14
    }

    /// 底部自定义 Tab 栏、顶部工具栏与悬浮按钮共用布局常量，避免各处零散取值。
    enum Layout {
        /// 52pt 按钮 + 上下 6pt 内边距 + 底部 4pt 留白。
        static let tabBarHeight: CGFloat = 68
        /// 顶部工具栏胶囊高度，左侧周期控件与右侧操作组保持一致。
        static let toolbarControlHeight: CGFloat = 36
        /// 悬浮按钮底边到屏幕底部的距离。
        /// `safeAreaInset` 只压缩滚动内容的安全区，页面本身仍铺到屏幕底部，所以这里必须显式叠加 Tab 栏高度。
        static let fabBottomOffset: CGFloat = tabBarHeight + Theme.Spacing.l
        /// 列表底部留白：按钮底边 + 按钮 56 + 28 呼吸，保证最后一笔流水不被按钮压住。
        static let fabClearance: CGFloat = fabBottomOffset + 84
        /// 页面底部避让：Tab 栏高度 + 12pt 呼吸。
        ///
        /// `safeAreaInset` 只压缩滚动安全区，页面本身仍铺到屏幕底部，列表最后一行会贴在玻璃栏下沿，
        /// 看起来就是「被 Tab 栏挡住」。所有列表页统一补这段，不要在单页里各写一个数字。
        static let tabBarClearance: CGFloat = tabBarHeight + 12
    }

    /// 字号规范：金额三档（26 / 17 / 13），统一圆体；等宽数字在调用处加 .monospacedDigit()
    enum Fonts {
        /// 超大金额：净资产、总资产
        static let amountXL = Font.system(size: 38, weight: .semibold, design: .rounded)
        /// 卡片主金额
        static let amountL = Font.system(size: 30, weight: .semibold, design: .rounded)
        /// 列表金额
        static let amountM = Font.system(size: 17, weight: .medium, design: .rounded)
        /// 辅助金额
        static let amountS = Font.system(size: 13, weight: .medium, design: .rounded)

        /// 自定义圆体金额（用于输入框等特例）
        static func amount(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
    }

    // 预设主题（只换强调色）
    struct Preset: Identifiable, Hashable {
        let id: String
        let name: String
        let hex: UInt32
    }

    static let presets: [Preset] = [
        Preset(id: "sage", name: "苔绿", hex: 0x526B60),
        Preset(id: "mist", name: "雾蓝", hex: 0x5B7C99),
        Preset(id: "bean", name: "豆绿", hex: 0x1F6F5C),
        Preset(id: "latte", name: "奶咖", hex: 0x9C7B5B),
        Preset(id: "ink", name: "墨黑", hex: 0x2B2B2E),
        Preset(id: "sakura", name: "樱粉", hex: 0xC98A9B),
        Preset(id: "lemon", name: "柠檬", hex: 0xB8952E)
    ]

    /// 图表配色：以主题色为起点，按黄金角 0.618 旋转色相，
    /// 保证相邻扇区颜色差得足够开（之前是线性小步长，颜色太接近）。
    static func chartPalette(_ count: Int) -> [Color] {
        guard count > 0 else { return [] }
        let base = UIColor(hexString: accentHex)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return Array(repeating: accent, count: count)
        }

        let goldenAngle: CGFloat = 0.618
        return (0..<count).map { index in
            let newHue = (hue + CGFloat(index) * goldenAngle).truncatingRemainder(dividingBy: 1)
            // 饱和度/亮度交替，进一步拉开明暗差
            let newSaturation = index % 2 == 0 ? CGFloat(0.62) : CGFloat(0.45)
            let newBrightness = index % 3 == 0 ? CGFloat(0.88) : CGFloat(0.72)
            return Color(uiColor: UIColor(hue: newHue, saturation: newSaturation, brightness: newBrightness, alpha: 1))
        }
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    init(hexString: String) {
        let cleaned = hexString.replacingOccurrences(of: "#", with: "")
        let value = UInt32(cleaned, radix: 16) ?? 0x5B7C99
        self.init(hex: value)
    }

    /// 明暗两套颜色
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }

    convenience init(hexString: String) {
        let cleaned = hexString.replacingOccurrences(of: "#", with: "")
        self.init(hex: UInt32(cleaned, radix: 16) ?? 0x5B7C99)
    }

    /// 与白色混合，用于深色模式下提亮品牌色
    func lightened(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        let t = min(max(amount, 0), 1)
        return UIColor(
            red: r + (1 - r) * t,
            green: g + (1 - g) * t,
            blue: b + (1 - b) * t,
            alpha: a
        )
    }
    /// 与黑色混合，用于金额主卡渐变末端，保持白字对比度。
    func darkened(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        let t = min(max(amount, 0), 1)
        return UIColor(red: r * (1 - t), green: g * (1 - t), blue: b * (1 - t), alpha: a)
    }
}

// MARK: - 统一样式

extension View {
    /// 统一卡片：动态背景 + 极细描边（深色下靠描边区分层次，而不是阴影）
    func cardStyle(radius: CGFloat = Theme.Radius.card, padding: CGFloat? = nil) -> some View {
        modifier(CardStyleModifier(radius: radius, padding: padding))
    }

    /// 顶部工具栏胶囊：周期控件与右侧操作组共用同一容器，消除边框/高度/留白不一致。
    func toolbarCapsuleStyle() -> some View {
        modifier(ToolbarCapsuleStyle())
    }

    /// 列表页统一避让悬浮 Tab 栏（Tab 栏高度 + 12pt 呼吸）。
    ///
    /// 只对滚动内容生效；页面顶部的固定按钮不用它，改用 `.safeAreaPadding(.bottom, ...)`。
    func ledgerTabBarClearance() -> some View {
        contentMargins(.bottom, Theme.Layout.tabBarClearance, for: .scrollContent)
    }
}

private struct CardStyleModifier: ViewModifier {
    let radius: CGFloat
    let padding: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(
                Theme.cardBackground,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.045), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.045), radius: 18, x: 0, y: 8)
    }
}

private struct ToolbarCapsuleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(height: Theme.Layout.toolbarControlHeight)
            .background(Theme.cardBackground.opacity(0.92), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

/// 内容区标题：主标题、辅助说明与可选右侧入口保持同一基线。
struct LedgerSectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LedgerIconBadge: View {
    let systemImage: String
    var tint: Color = Theme.accent
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct PremiumEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            LedgerIconBadge(systemImage: systemImage, tint: Theme.accent, size: 56)
            VStack(spacing: Theme.Spacing.s) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl + Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.xl)
    }
}

struct SoftPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}
