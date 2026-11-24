import Foundation

/// 金额工具：一切金额以「分」为单位的 Int64 存储，禁止 Double。
enum Money {
    static let symbol = "¥"

    // MARK: - 格式化

    /// 123456 -> "¥1,234.56"
    static func format(_ minor: Int64, showSign: Bool = false) -> String {
        let negative = minor < 0
        let magnitude = negative ? (minor == Int64.min ? Int64.max : -minor) : minor
        let yuan = magnitude / 100
        let cents = magnitude % 100
        let centsText = cents < 10 ? "0\(cents)" : "\(cents)"
        var text = symbol + groupDigits(yuan) + "." + centsText
        if negative {
            text = "-" + text
        } else if showSign && minor > 0 {
            text = "+" + text
        }
        return text
    }

    /// 123456 -> "1,234.56"（不带货币符号）
    static func formatPlain(_ minor: Int64) -> String {
        let negative = minor < 0
        let magnitude = negative ? (minor == Int64.min ? Int64.max : -minor) : minor
        let yuan = magnitude / 100
        let cents = magnitude % 100
        let centsText = cents < 10 ? "0\(cents)" : "\(cents)"
        let text = groupDigits(yuan) + "." + centsText
        return negative ? "-" + text : text
    }

    private static func groupDigits(_ value: Int64) -> String {
        let digits = String(value)
        guard digits.count > 3 else { return digits }
        var result = ""
        var counter = 0
        for ch in digits.reversed() {
            if counter == 3 {
                result = "," + result
                counter = 0
            }
            result = String(ch) + result
            counter += 1
        }
        return result
    }

    // MARK: - 解析

    /// "¥1,234.56" / "1234.56" / "1234" -> 123456
    static func parse(_ text: String) -> Int64? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        for junk in [symbol, ",", "，", " ", "元"] {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        guard !s.isEmpty else { return nil }
        guard let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return minor(value)
    }

    // MARK: - Decimal 互转

    static func decimal(_ minor: Int64) -> Decimal {
        Decimal(minor) / 100
    }

    /// 四舍五入到「分」
    static func minor(_ value: Decimal) -> Int64 {
        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
