import Foundation

struct ZipEntry {
    let name: String
    let data: Data
}

/// 极简 ZIP 打包（仅 store 方式，不压缩）。
/// iOS 没有公开的 zip 写入 API，引第三方库又违背「零依赖」的约束，
/// 所以这里只实现必要的最小子集：本地文件头 + 中央目录 + 结束记录。
enum ZipWriter {
    static func archive(_ entries: [ZipEntry]) -> Data {
        var output = Data()
        var central = Data()
        var offset: UInt32 = 0
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = (1 << 5) | 1 // 1980-01-01

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let localOffset = offset

            var local = Data()
            local.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
            local.append(uint16: 20)       // 解压所需版本
            local.append(uint16: 0x0800)   // 文件名 UTF-8
            local.append(uint16: 0)        // 压缩方式：store
            local.append(uint16: dosTime)
            local.append(uint16: dosDate)
            local.append(uint32: crc)
            local.append(uint32: size)
            local.append(uint32: size)
            local.append(uint16: UInt16(nameData.count))
            local.append(uint16: 0)        // extra 长度
            local.append(nameData)

            output.append(local)
            output.append(entry.data)

            offset += UInt32(local.count) + size

            central.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
            central.append(uint16: 20)
            central.append(uint16: 20)
            central.append(uint16: 0x0800)
            central.append(uint16: 0)
            central.append(uint16: dosTime)
            central.append(uint16: dosDate)
            central.append(uint32: crc)
            central.append(uint32: size)
            central.append(uint32: size)
            central.append(uint16: UInt16(nameData.count))
            central.append(uint16: 0)
            central.append(uint16: 0)
            central.append(uint16: 0)
            central.append(uint16: 0)
            central.append(uint32: 0)      // 外部属性
            central.append(uint32: localOffset)
            central.append(nameData)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        output.append(uint16: 0)
        output.append(uint16: 0)
        output.append(uint16: UInt16(entries.count))
        output.append(uint16: UInt16(entries.count))
        output.append(uint32: UInt32(central.count))
        output.append(uint32: centralOffset)
        output.append(uint16: 0)

        return output
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = {
        (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crcTable[index]
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func append(uint32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
