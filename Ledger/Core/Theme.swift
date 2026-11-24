import SwiftUI

/// 视觉 token：颜色、间距、圆角。所有视图只能引用这里的值。
enum Theme {
    // 强调色（可在设置里替换预设）
    static let accent = Color(hex: 0x5B7C99)

    // 语义色
    static let income = Color(hex: 0x2E9E6B)
    static let warning = Color(hex: 0xC2410C)
    static let danger = Color(hex: 0xDC2626)
    static let transfer = Color.secondary

    // 背景
    static let pageBackground = Color(hex: 0xF6F6F7)
    static let cardBackground = Color.white

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
}
