import Foundation

struct ParsedReceipt {
    var amountMinor: Int64?
    var payee: String?
    var confidence: Double
    var rawText: String
}

/// 从截图 OCR 文本里解析金额与商户。
/// 只做规则，不联网；识别不到就返回 nil，交给用户手填。
enum ScreenshotParser {
    /// 出现这些词的行，金额不可信（余额、优惠、额度等）
    private static let noiseKeywords = [
        "余额", "可用", "额度", "优惠", "红包", "积分", "立减", "抵扣",
        "手续费", "服务费", "已省", "原价", "抹零", "找零"
    ]

    private static let payeeKeywords = ["收款方", "商户全称", "商户名称", "付款给", "转账给", "收款人", "商家"]

    private static let successKeywords = ["付款成功", "支付成功", "转账成功", "交易成功", "已支付"]

    static func parse(lines: [OCRLine]) -> ParsedReceipt {
        let texts = lines.map { $0.text }
        let rawText = texts.joined(separator: "\n")

        let amount = extractAmount(lines: lines)
        let payee = extractPayee(texts: texts)

        var confidence = 0.0
        if amount != nil { confidence += 0.55 }
        if payee != nil { confidence += 0.2 }
        if texts.contains(where: { line in successKeywords.contains(where: { line.contains($0) }) }) {
            confidence += 0.2
        }

        return ParsedReceipt(
            amountMinor: amount,
            payee: payee,
            confidence: min(1.0, confidence),
            rawText: rawText
        )
    }

    // MARK: - 金额

    static func extractAmount(lines: [OCRLine]) -> Int64? {
        var candidates: [(minor: Int64, score: CGFloat)] = []

        for line in lines {
            let text = line.text
            if noiseKeywords.contains(where: { text.contains($0) }) { continue }
            guard let minor = firstAmount(in: text), minor > 0 else { continue }
            // 字越大越可能是主金额
            var score = line.height
            if successKeywords.contains(where: { text.contains($0) }) {
                score += 0.05
            }
            candidates.append((minor, score))
        }

        guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }
        return best.minor
    }

    /// 抓取一行里第一个像金额的数字
    static func firstAmount(in text: String) -> Int64? {
        let pattern = #"(?<![\d.])(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard let match = matches.first else { return nil }

        guard let wholeRange = Range(match.range(at: 1), in: text) else { return nil }
        let whole = text[wholeRange].replacingOccurrences(of: ",", with: "")

        var fraction = "00"
        if match.range(at: 2).location != NSNotFound, let fractionRange = Range(match.range(at: 2), in: text) {
            let digits = String(text[fractionRange])
            fraction = digits.count == 1 ? digits + "0" : digits
        }

        guard let yuan = Int64(whole), let cents = Int64(fraction) else { return nil }
        return yuan * 100 + cents
    }

    // MARK: - 商户

    static func extractPayee(texts: [String]) -> String? {
        for (index, text) in texts.enumerated() {
            for keyword in payeeKeywords where text.contains(keyword) {
                // 同一行「收款方：星巴克」
                if let separatorIndex = text.firstIndex(where: { $0 == ":" || $0 == "：" }) {
                    let value = String(text[text.index(after: separatorIndex)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return clean(value) }
                }
                // 关键词单独一行，下一行是名字
                if index + 1 < texts.count {
                    let next = texts[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !next.isEmpty, !next.contains("¥"), !next.contains("元") {
                        return clean(next)
                    }
                }
            }
        }
        return nil
    }

    private static func clean(_ value: String) -> String {
        var text = value
        for suffix in ["有限公司", "有限责任公司", "科技", "商贸", "分公司"] {
            text = text.replacingOccurrences(of: suffix, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
