import Foundation

/// 通用账单行（支付宝 / 微信 / 银行 CSV 解析结果）
struct BillRow: Identifiable, Equatable {
    let id = UUID()
    let occurredAt: Date
    let amountMinor: Int64
    let isIncome: Bool
    let counterparty: String?
    let subject: String?
    let externalId: String?
    let rawLine: String
}

enum BillSource: String, CaseIterable {
    case alipay
    case wechat
    case generic

    var displayName: String {
        switch self {
        case .alipay: return "支付宝"
        case .wechat: return "微信"
        case .generic: return "通用 CSV"
        }
    }
}

/// 账单 CSV 解析：列名别名匹配 + 编码兜底 + 状态过滤。
/// 支付宝/微信导出的列名与顺序随版本变化，所以一律按表头语义取列。
enum BillCSVParser {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct ParseResult {
        let rows: [BillRow]
        let source: BillSource
        let skipped: Int
    }

    // 语义 → 可能的列名
    private static let aliases: [String: [String]] = [
        "time": ["交易时间", "交易创建时间", "发生时间", "时间", "记账时间", "交易日期"],
        "direction": ["收/支", "收支类型", "收付款", "收支"],
        "amount": ["金额", "金额(元)", "交易金额", "发生金额"],
        "counterparty": ["交易对方", "对方账号", "商户名称", "对方"],
        "subject": ["商品说明", "商品", "商品名称", "交易分类", "备注"],
        "status": ["交易状态", "当前状态", "状态"],
        "orderId": ["交易订单号", "交易单号", "交易号", "商户订单号"]
    ]

    private static let timeFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy-MM-dd"
    ]

    static func parse(text: String) throws -> ParseResult {
        var raw = text
        if raw.hasPrefix("\u{FEFF}") { raw.removeFirst() }
        let lines = splitRecords(raw).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerIndex = lines.firstIndex(where: { line in
            let normalized = normalizeHeader(line)
            return normalized.contains("交易时间") || normalized.contains("交易创建时间")
                || normalized.contains("发生时间") || normalized.contains("记账时间")
                || normalized.contains("交易日期")
        }) else {
            throw Failure(message: "找不到表头（需要包含「交易时间」等列）")
        }

        let delimiter = detectDelimiter(in: lines[headerIndex])
        let headers = splitFields(lines[headerIndex], delimiter: delimiter)
            .map { normalizeHeader($0) }
        var columnIndex: [String: Int] = [:]
        for (key, names) in aliases {
            for name in names {
                let normalizedName = normalizeHeader(name)
                if let index = headers.firstIndex(where: { $0 == normalizedName || $0.contains(normalizedName) }) {
                    columnIndex[key] = index
                    break
                }
            }
        }

        guard let timeIndex = columnIndex["time"], let amountIndex = columnIndex["amount"] else {
            throw Failure(message: "表头缺少「交易时间」或「金额」列")
        }

        // 来源标识常出现在文件抬头的说明行里，不能只看表头
        let probe = raw
        let source: BillSource = probe.contains("支付宝") ? .alipay
            : (probe.contains("微信") ? .wechat : .generic)

        var rows: [BillRow] = []
        var skipped = 0

        for line in lines[(headerIndex + 1)...] {
            let fields = splitFields(line, delimiter: delimiter)

            func value(_ key: String) -> String? {
                guard let index = columnIndex[key], index < fields.count else { return nil }
                let text = fields[index].trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? nil : text
            }

            guard let timeText = value("time") ?? (timeIndex < fields.count ? fields[timeIndex] : nil),
                  let date = parseDate(timeText) else {
                skipped += 1
                continue
            }
            guard let amountText = value("amount") ?? (amountIndex < fields.count ? fields[amountIndex] : nil),
                  let amount = Money.parse(amountText), amount != 0 else {
                skipped += 1
                continue
            }

            let direction = value("direction") ?? ""
            if direction.contains("不计收支") {
                skipped += 1
                continue
            }
            let isIncome: Bool
            if direction.contains("收入") {
                isIncome = true
            } else if direction.contains("支出") {
                isIncome = false
            } else {
                // 转账、方向缺失等不能安全推断的记录不冒充支出导入。
                skipped += 1
                continue
            }
            if let status = value("status"),
               ["退款成功", "已关闭", "交易关闭", "已全额退款", "失败"].contains(where: { status.contains($0) }) {
                skipped += 1
                continue
            }

            rows.append(
                BillRow(
                    occurredAt: date,
                    amountMinor: amount == Int64.min ? Int64.max : abs(amount),
                    isIncome: isIncome,
                    counterparty: value("counterparty"),
                    subject: value("subject"),
                    externalId: value("orderId"),
                    rawLine: line
                )
            )
        }

        guard !rows.isEmpty else {
            throw Failure(message: "没有解析到有效记录")
        }
        return ParseResult(rows: rows, source: source, skipped: skipped)
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in timeFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// 表头规范化：全角括号转半角、去掉空格，兼容不同版本导出。
    static func normalizeHeader(_ text: String) -> String {
        text
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 自动识别逗号 / 分号 / Tab 分隔（银行导出常见）。
    static func detectDelimiter(in headerLine: String) -> Character {
        if headerLine.contains("\t") { return "\t" }
        if headerLine.contains(";"), !headerLine.contains(",") { return ";" }
        return ","
    }

    /// 按 CSV 记录切分，支持 CRLF 以及引号字段内的换行；字段内容保持原样供 splitFields 解码。
    static func splitRecords(_ text: String) -> [String] {
        var records: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                current.append(character)
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append(characters[index + 1])
                    index += 2
                    continue
                }
                inQuotes.toggle()
                index += 1
            } else if (character == "\n" || character == "\r"), !inQuotes {
                records.append(current)
                current = ""
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 2
                } else {
                    index += 1
                }
            } else {
                current.append(character)
                index += 1
            }
        }
        records.append(current)
        return records
    }

    /// 支持引号内逗号与双引号转义
    static func splitFields(_ line: String, delimiter: Character = ",") -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                inQuotes.toggle()
                index += 1
            } else if character == delimiter, !inQuotes {
                fields.append(current)
                current = ""
                index += 1
            } else {
                current.append(character)
                index += 1
            }
        }
        fields.append(current)
        return fields
    }
}
