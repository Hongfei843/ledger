import SwiftUI

/// 分类图标风格。目前支持 Emoji 与线条图标，后续可扩展扁平/拟物。
enum IconStyle: String, CaseIterable, Identifiable {
    case emoji
    case symbol

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .emoji: return "Emoji"
        case .symbol: return "线条图标"
        }
    }
}

enum CategoryIcon {
    static let styleKey = "ui.iconStyle"

    /// 分类名 → SF Symbol
    static func symbol(for name: String) -> String {
        if let symbol = mapping[name] { return symbol }
        // 二级分类常带后缀，做一次包含匹配
        for (key, value) in mapping where name.contains(key) {
            return value
        }
        return "tag"
    }

    private static let mapping: [String: String] = [
        // 支出
        "餐饮": "fork.knife",
        "咖啡奶茶": "cup.and.saucer",
        "外卖": "takeoutbag.and.cup.and.straw",
        "买菜": "basket",
        "水果": "leaf",
        "零食": "birthday.cake",
        "烟酒": "wineglass",
        "交通": "tram",
        "打车": "car",
        "公交地铁": "tram.fill",
        "加油": "fuelpump",
        "停车": "parkingsign",
        "购物": "bag",
        "服饰": "tshirt",
        "美妆": "sparkles",
        "数码": "laptopcomputer",
        "日用": "shippingbox",
        "家装": "hammer",
        "居住": "house",
        "物业": "building.2",
        "水电燃气": "bolt",
        "宽带": "wifi",
        "话费": "antenna.radiowaves.left.and.right",
        "通讯": "antenna.radiowaves.left.and.right",
        "娱乐": "gamecontroller",
        "电影": "film",
        "游戏": "gamecontroller.fill",
        "健身": "figure.run",
        "医疗": "cross.case",
        "药品": "pills",
        "体检": "stethoscope",
        "保险": "shield",
        "教育": "graduationcap",
        "书籍": "books.vertical",
        "人情送礼": "gift",
        "人情": "gift",
        "旅行": "airplane",
        "住宿": "bed.double",
        "宠物": "pawprint",
        "订阅服务": "bell",
        "利息支出": "building.columns",
        "手续费": "doc.text",
        "报销差额": "paperclip",
        "税费": "percent",
        "其他": "shippingbox",
        // 收入
        "工资": "banknote",
        "奖金": "trophy",
        "年终奖": "gift.fill",
        "兼职": "briefcase",
        "报销收入": "doc.text.fill",
        "投资收益": "chart.line.uptrend.xyaxis",
        "利息收入": "percent",
        "红包": "gift",
        "退款": "arrow.uturn.backward",
        "礼金": "envelope",
        "其他收入": "shippingbox"
    ]
}

/// 统一的分类图标视图，随设置切换风格。
struct CategoryIconView: View {
    let emoji: String
    let name: String
    let colorHex: String
    var size: CGFloat = 44

    @AppStorage(CategoryIcon.styleKey) private var styleRaw: String = IconStyle.symbol.rawValue

    private var tint: Color {
        Color(hexString: colorHex)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(tint.opacity(0.13))
            if styleRaw == IconStyle.symbol.rawValue {
                Image(systemName: CategoryIcon.symbol(for: name))
                    .font(.system(size: size * 0.42, weight: .regular))
                    .foregroundStyle(tint)
            } else {
                Text(emoji)
                    .font(.system(size: size * 0.46))
            }
        }
        .frame(width: size, height: size)
    }
}

extension CategoryIconView {
    init(category: Category?, size: CGFloat = 44) {
        self.init(
            emoji: category?.iconEmoji ?? "📦",
            name: category?.name ?? "其他",
            colorHex: category?.colorHex ?? "5B7C99",
            size: size
        )
    }
}
