import XCTest
@testable import Ledger

final class ZipWriterTests: XCTestCase {
    func testCRC32KnownValue() {
        // "hello" 的 CRC32 是 0x3610A686
        XCTAssertEqual(ZipWriter.crc32(Data("hello".utf8)), 0x3610A686)
    }

    func testArchiveStructure() {
        let entries = [
            ZipEntry(name: "a.txt", data: Data("hello".utf8)),
            ZipEntry(name: "dir/b.md", data: Data("# 标题".utf8))
        ]
        let data = ZipWriter.archive(entries)

        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "应以本地文件头开头")

        let tail = [UInt8](data.suffix(22))
        XCTAssertEqual(Array(tail.prefix(4)), [0x50, 0x4B, 0x05, 0x06], "应以中央目录结束记录收尾")

        // 结束记录里的条目数（偏移 10、12）应为 2
        let count1 = UInt16(tail[10]) | (UInt16(tail[11]) << 8)
        let count2 = UInt16(tail[12]) | (UInt16(tail[13]) << 8)
        XCTAssertEqual(count1, 2)
        XCTAssertEqual(count2, 2)
    }

    func testUnicodeFileName() {
        let data = ZipWriter.archive([ZipEntry(name: "中文名.csv", data: Data("1,2".utf8))])
        XCTAssertGreaterThan(data.count, 30)
    }
}
