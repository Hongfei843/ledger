import Foundation

/// 把导入数据里的分类名映射到本地已有分类。
/// 目的：外部账单的分类叫法五花八门（「美食」「App 订阅」「电费」），
/// 直接建新分类会让分类表越滚越乱，应该落到已有的宽口径分类上。
enum CategoryMatcher {
    private struct Rule {
        let keywords: [String]
        let target: String
    }

    /// 支出侧关键词 → 目标分类
    private static let expenseRules: [Rule] = [
        Rule(keywords: ["餐饮", "美食", "外卖", "咖啡", "奶茶", "零食", "买菜", "水果", "正餐", "早餐", "午餐", "晚餐", "夜宵", "烟酒", "食品"], target: "餐饮"),
        Rule(keywords: ["交通", "打车", "地铁", "公交", "加油", "停车", "过路", "高铁", "火车", "机票", "滴滴"], target: "交通"),
        Rule(keywords: ["购物", "服饰", "衣服", "美妆", "化妆", "数码", "电商", "家装", "家具", "家电", "鞋"], target: "购物"),
        Rule(keywords: ["日用", "生活用品", "超市", "清洁", "纸品"], target: "日用"),
        Rule(keywords: ["居住", "房租", "物业", "水电", "电费", "水费", "燃气", "宽带", "暖气", "维修"], target: "居住"),
        Rule(keywords: ["通讯", "话费", "流量", "手机费"], target: "通讯"),
        Rule(keywords: ["娱乐", "电影", "游戏", "健身", "运动", "演出", "KTV", "旅游娱乐"], target: "娱乐"),
        Rule(keywords: ["医疗", "药品", "体检", "医院", "挂号", "看病", "牙"], target: "医疗"),
        Rule(keywords: ["教育", "书籍", "课程", "培训", "学费", "考试", "文具"], target: "教育"),
        Rule(keywords: ["人情", "礼金", "送礼", "红包", "婚礼", "份子"], target: "人情"),
        Rule(keywords: ["旅行", "旅游", "住宿", "酒店", "民宿", "景点", "门票"], target: "旅行"),
        Rule(keywords: ["宠物", "猫", "狗", "宠物医院"], target: "宠物"),
        Rule(keywords: ["订阅", "会员", "App", "软件", "服务费"], target: "订阅服务"),
        Rule(keywords: ["利息", "房贷利息", "贷款利息"], target: "利息支出"),
        Rule(keywords: ["手续费", "服务手续费", "提现费"], target: "手续费"),
        Rule(keywords: ["保险", "保费"], target: "保险"),
        Rule(keywords: ["税", "个税", "税费", "罚款"], target: "税费"),
        Rule(keywords: ["报销差额", "差额"], target: "报销差额")
    ]

    /// 收入侧关键词 → 目标分类
    private static let incomeRules: [Rule] = [
        Rule(keywords: ["工资", "薪", "薪水", "月薪"], target: "工资"),
        Rule(keywords: ["奖金", "年终", "绩效", "提成"], target: "奖金"),
        Rule(keywords: ["兼职", "外快", "副业"], target: "兼职"),
        Rule(keywords: ["报销", "退款报销"], target: "报销收入"),
        Rule(keywords: ["投资", "理财", "利息", "分红", "基金", "股票"], target: "投资收益"),
        Rule(keywords: ["红包", "礼金", "压岁"], target: "红包"),
        Rule(keywords: ["退款", "退回", "退货"], target: "退款")
    ]

    /// 返回能落到的已有分类；匹配不上则返回「其他」
    static func match(name: String, kind: CategoryKind, categories: [Category]) -> Category? {
        let pool = categories.filter { $0.deletedAt == nil && !$0.isArchived && $0.kind == kind }
        guard !pool.isEmpty else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespaces)

        // 1. 完全同名
        if let exact = pool.first(where: { $0.name == trimmed }) {
            return exact
        }

        // 2. 关键词包含匹配（取最长命中，避免「宠物医院」被「医院」抢走又不像宠物）
        let rules = kind == .income ? incomeRules : expenseRules
        var best: (target: String, length: Int)?
        for rule in rules {
            for keyword in rule.keywords {
                if trimmed.contains(keyword) {
                    if let current = best {
                        if keyword.count > current.length {
                            best = (rule.target, keyword.count)
                        }
                    } else {
                        best = (rule.target, keyword.count)
                    }
                }
            }
        }
        if let best, let matched = pool.first(where: { $0.name == best.target }) {
            return matched
        }

        // 3. 兜底「其他」
        return pool.first(where: { $0.name == "其他" })
    }
}
