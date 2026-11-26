import Foundation

/// 从 OCR 文本里识别出的付款方式（银行/平台 + 卡类型 + 后四位）。
struct DetectedPaymentMethod: Equatable {
    let bankId: String?
    let bankName: String
    let accountType: AccountType
    let cardTail: String?

    /// 给用户看的短名称，如「中信银行 ··1368」
    var displayName: String {
        var text = bankName
        if let cardTail, !cardTail.isEmpty { text += " ··\(cardTail)" }
        return text
    }

    /// 建议新建的账户名，如「中信银行储蓄卡 1368」
    var suggestedAccountName: String {
        var text = bankName
        if accountType == .debit || accountType == .credit {
            text += accountType.displayName
        }
        if let cardTail, !cardTail.isEmpty { text += " \(cardTail)" }
        return text
    }
}

/// 从截图 OCR 文本识别付款方式。纯规则，不联网。
enum PaymentMethodDetector {
    private static let labeledTailPattern = #"(?:尾号|后四位|最后四位|末四位|卡号|账户)[^0-9]{0,8}(\d{4})"#
    private static let looseTailPattern = #"(?<!\d)(\d{4})(?!\d)"#

    static func detect(texts: [String]) -> DetectedPaymentMethod? {
        let joined = texts.joined(separator: "\n")
        let presets = BankPreset.all.sorted { $0.name.count > $1.name.count }

        var matched: BankPreset?
        var matchedLine: String?
        for line in texts {
            guard let preset = presets.first(where: { line.contains($0.name) }) else { continue }
            if matched == nil || preset.name.count > (matched?.name.count ?? 0) {
                matched = preset
                matchedLine = line
            }
        }

        // 支付宝/微信等平台，有时只出现简称
        if matched == nil {
            let aliases: [(alias: String, id: String)] = [
                ("支付宝", "alipay"), ("微信", "wechat"), ("花呗", "huabei"),
                ("云闪付", "unionpay"), ("京东白条", "jdbt"), ("抖音月付", "douyin")
            ]
            for item in aliases where joined.contains(item.alias) {
                matched = BankPreset.all.first { $0.id == item.id }
                matchedLine = joined
                break
            }
        }

        guard let preset = matched else { return nil }

        let line = matchedLine ?? joined
        var accountType = preset.suggestedType
        if line.contains("信用卡") {
            accountType = .credit
        } else if line.contains("储蓄卡") || line.contains("借记卡") {
            accountType = .debit
        } else if line.contains("余额宝") || line.contains("零钱") {
            accountType = .ewallet
        } else if line.contains("花呗") {
            accountType = .bnpl
        }

        var tail: String?
        if let regex = try? NSRegularExpression(pattern: labeledTailPattern) {
            let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
            if let match = regex.firstMatch(in: joined, range: range),
               let tailRange = Range(match.range(at: 1), in: joined) {
                tail = String(joined[tailRange])
            }
        }
        if tail == nil,
           line.contains("卡"),
           let regex = try? NSRegularExpression(pattern: looseTailPattern) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, range: range)
            if let last = matches.last, let tailRange = Range(last.range(at: 1), in: line) {
                tail = String(line[tailRange])
            }
        }

        return DetectedPaymentMethod(
            bankId: preset.id,
            bankName: preset.name,
            accountType: accountType,
            cardTail: tail
        )
    }
}
