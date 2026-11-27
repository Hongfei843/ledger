import Foundation

/// Cookie 记账导出的账单记录（已解析）
struct CookieRecord: Equatable {
    let externalId: String?
    let occurredAt: Date
    let isIncome: Bool
    let primaryCategory: String
    let secondaryCategory: String?
    let amountMinor: Int64
    let note: String?
    let accountName: String?
    let bookName: String?
    let tags: [String]
    let emoji: String?
    let needReimbursement: Bool
}

/// 解析 Cookie 记账导出的 CSV。
///
/// 实际格式（2026-11 导出样本）：
/// ```
/// Cookie账单(全部)
/// 时间,收支,一级分类,二级分类,金额,币种,备注,卡包,账本,标签,其他
/// 2026-11-24 10:40:22,支出,App 订阅,,¥10,CNY,DSH,,,,eyJpZCI6...
/// ```
/// 第 1 行是标题，第 2 行是表头，之后是数据。
/// `其他` 列是 base64 的 JSON，含原始 `id`、`firstTypeEmoji`、`needReimbursement`。
enum CookieCSVImporter {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    // MARK: - 入口

    static func parse(text: String) throws -> [CookieRecord] {
        var raw = text
        if raw.hasPrefix("\u{FEFF}") {
            raw.removeFirst()
        }
        let lines = BillCSVParser.splitRecords(raw).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else {
            throw Failure(message: "文件是空的")
        }

        // 找到表头行
        guard let headerIndex = lines.firstIndex(where: { $0.contains("时间") && $0.contains("金额") }) else {
            throw Failure(message: "找不到表头，可能不是 Cookie 导出的账单")
        }

        let headers = splitFields(lines[headerIndex]).map { $0.trimmingCharacters(in: .whitespaces) }
        let indexOf = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })

        func column(_ row: [String], _ name: String) -> String? {
            guard let index = indexOf[name], index < row.count else { return nil }
            let value = row[index].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }

        var records: [CookieRecord] = []
        for line in lines[(headerIndex + 1)...] {
            let row = splitFields(line)
            guard row.count >= 3 else { continue }

            guard let timeText = column(row, "时间"),
                  let date = dateFormatter.date(from: timeText) else { continue }

            let amountText = column(row, "金额") ?? ""
            guard let amount = Money.parse(amountText), amount != 0 else { continue }

            let direction = column(row, "收支") ?? ""
            let isIncome: Bool
            if direction.contains("收入") {
                isIncome = true
            } else if direction.contains("支出") {
                isIncome = false
            } else {
                // 转账等未建模类型不能在导入时静默变成支出。
                continue
            }

            let primary = column(row, "一级分类") ?? "其他"
            let secondary = column(row, "二级分类")

            let meta = decodeMeta(column(row, "其他"))

            let tagsText = column(row, "标签")
            let tags = tagsText.map { text in
                text.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " }).map(String.init)
            } ?? []

            records.append(
                CookieRecord(
                    externalId: meta.id,
                    occurredAt: date,
                    isIncome: isIncome,
                    primaryCategory: primary,
                    secondaryCategory: secondary,
                    amountMinor: amount == Int64.min ? Int64.max : abs(amount),
                    note: column(row, "备注"),
                    accountName: column(row, "卡包"),
                    bookName: column(row, "账本"),
                    tags: tags,
                    emoji: decodeEmoji(meta.emojiCode),
                    needReimbursement: meta.needReimbursement
                )
            )
        }

        return records
    }

    // MARK: - 元数据

    private struct Meta {
        var id: String?
        var emojiCode: String?
        var needReimbursement: Bool
    }

    private static func decodeMeta(_ base64: String?) -> Meta {
        guard let base64,
              let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Meta(id: nil, emojiCode: nil, needReimbursement: false)
        }
        return Meta(
            id: object["id"] as? String,
            emojiCode: object["firstTypeEmoji"] as? String,
            needReimbursement: object["needReimbursement"] as? Bool ?? false
        )
    }

    /// Cookie 里 emoji 存成 "u1f4f1" 这种形式
    static func decodeEmoji(_ code: String?) -> String? {
        guard let code, code.hasPrefix("u"),
              let value = UInt32(code.dropFirst(), radix: 16),
              let scalar = UnicodeScalar(value) else {
            return nil
        }
        return String(Character(scalar))
    }

    // MARK: - CSV

    /// 支持带引号字段的 CSV 单行切分
    static func splitFields(_ line: String) -> [String] {
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
            } else if character == ",", !inQuotes {
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
