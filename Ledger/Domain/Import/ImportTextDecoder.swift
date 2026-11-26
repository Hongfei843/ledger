import Foundation

/// 导入文件的文本编码兜底：UTF-8（含 BOM）→ UTF-16 BOM → GB18030 → GBK。
/// 国内账单/银行导出的 CSV 常见 GB18030（GBK 超集）编码。
enum ImportTextDecoder {
    static func decode(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: Data(data.dropFirst(3)), encoding: .utf8)
        }
        if data.count >= 2 {
            let first = data[data.startIndex]
            let second = data[data.index(after: data.startIndex)]
            if first == 0xFF, second == 0xFE {
                return String(data: data, encoding: .utf16LittleEndian)
            }
            if first == 0xFE, second == 0xFF {
                return String(data: data, encoding: .utf16BigEndian)
            }
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: String.Encoding(rawValue: 0x80000632)) {
            return text
        }
        return String(data: data, encoding: String.Encoding(rawValue: 0x80000631))
    }
}
