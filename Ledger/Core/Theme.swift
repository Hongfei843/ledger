import SwiftUI
import UIKit

/// 视觉 token：颜色、间距、圆角。所有视图只能引用这里的值。
enum Theme {
    /// 强调色存储键（UserDefaults / AppStorage 共用）
    static let accentHexKey = "ui.accentHex"
    static let defaultAccentHex = "5B7C99"

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

    // 背景：使用系统动态色，自动跟随深色模式
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

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
        static let card: CGFloat = 16
        static let button: CGFloat = 12
        static let sheet: CGFloat = 20
        static let icon: CGFloat = 22
    }

    // 预设主题（只换强调色）
    struct Preset: Identifiable, Hashable {
        let id: String
        let name: String
        let hex: UInt32
    }

    static let presets: [Preset] = [
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
}

// MARK: - 统一样式

extension View {
    /// 统一卡片：动态背景 + 极细描边（深色下靠描边区分层次，而不是阴影）
    func cardStyle(radius: CGFloat = Theme.Radius.card, padding: CGFloat? = nil) -> some View {
        modifier(CardStyleModifier(radius: radius, padding: padding))
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
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}
