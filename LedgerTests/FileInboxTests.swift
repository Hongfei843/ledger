import XCTest
import UniformTypeIdentifiers
@testable import Ledger

final class FileInboxTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        tempDir = nil
    }

    private func write(_ name: String, contents: Data) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    func testKindByExtension() {
        XCTAssertEqual(FileInbox.kind(of: URL(fileURLWithPath: "/a/b.csv")), .csv)
        XCTAssertEqual(FileInbox.kind(of: URL(fileURLWithPath: "/a/b.CSV")), .csv)
        XCTAssertEqual(FileInbox.kind(of: URL(fileURLWithPath: "/a/b.txt")), .csv)
        XCTAssertEqual(FileInbox.kind(of: URL(fileURLWithPath: "/a/b.ledgerbak")), .backup)
        XCTAssertEqual(FileInbox.kind(of: URL(fileURLWithPath: "/a/b.json")), .backup)
        XCTAssertEqual(FileInbox.kind(of: URL(fileURLWithPath: "/a/b.png")), .image)
        XCTAssertEqual(FileInbox.kind(of: URL(fileURLWithPath: "/a/b.JPEG")), .image)
    }

    func testSniffKindWithoutExtension() throws {
        let json = try write("noext-json", contents: Data("{\"format\":\"ledger-encrypted-backup\"}".utf8))
        XCTAssertEqual(FileInbox.kind(of: json), .backup)

        let csv = try write("noext-csv", contents: Data("时间,收支,金额\n2026-01-01,支出,12.00\n".utf8))
        XCTAssertEqual(FileInbox.kind(of: csv), .csv)

        let png = try write("noext-png", contents: Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02]))
        XCTAssertEqual(FileInbox.kind(of: png), .image)
    }

    func testCandidatesSkipsInternalLogAndDirectories() throws {
        _ = try write("账单.csv", contents: Data("时间,收支\n".utf8))
        _ = try write("备份.ledgerbak", contents: Data([0x41]))
        _ = try write("写入失败日志.txt", contents: Data("日志".utf8))
        let sub = tempDir.appendingPathComponent("AutoBackup", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data([0x41]).write(to: sub.appendingPathComponent("恢复前自动备份-a.ledgerbak"))

        let files = FileInbox.candidates(in: [tempDir])
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains { $0.kind == .csv && $0.name == "账单.csv" })
        XCTAssertTrue(files.contains { $0.kind == .backup && $0.name == "备份.ledgerbak" })
        XCTAssertFalse(files.contains { $0.name.hasPrefix("写入失败日志") })
        // 子目录里的文件不该被列出来
        XCTAssertFalse(files.contains { $0.name.hasPrefix("恢复前自动备份") })
    }

    func testCandidatesSortedByModifiedDesc() throws {
        let old = try write("old.csv", contents: Data("a\n".utf8))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: old.path)
        let new = try write("new.csv", contents: Data("b\n".utf8))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 5000)], ofItemAtPath: new.path)

        let files = FileInbox.candidates(in: [tempDir])
        XCTAssertEqual(files.first?.name, "new.csv")
    }

    func testImportableCopyOfExternalFileLandsInImportFolder() throws {
        let external = try write("外部账单.csv", contents: Data("时间,收支\n".utf8))
        let copy = try FileInbox.importableCopy(of: external)
        XCTAssertTrue(copy.path.hasPrefix(FileInbox.documents.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(copy.lastPathComponent, "外部账单.csv")
        FileInbox.consume(copy)
    }

    func testImportableCopyInsideContainerIsReturnedAsIs() throws {
        let inside = try FileInbox.ensureImportFolder().appendingPathComponent("已在容器.csv")
        try Data("时间,收支\n".utf8).write(to: inside)
        let result = try FileInbox.importableCopy(of: inside)
        XCTAssertEqual(result.path, inside.path)
        try? FileManager.default.removeItem(at: inside)
    }

    func testImportableCopyNameCollisionGetsSuffix() throws {
        let first = try write("同名.csv", contents: Data("x\n".utf8))
        _ = try FileInbox.importableCopy(of: first)
        let second = try write("同名.csv", contents: Data("y\n".utf8))
        let secondCopy = try FileInbox.importableCopy(of: second)
        XCTAssertNotEqual(secondCopy.lastPathComponent, "同名.csv")
        XCTAssertTrue(secondCopy.lastPathComponent.hasPrefix("同名-"))

        // 清理：容器里留下的副本
        for file in FileInbox.candidates() where file.name.hasPrefix("同名") {
            FileInbox.consume(file.url)
        }
    }

    func testDataCopyFallbackWritesIntoImportFolder() throws {
        let external = try write("兜底.csv", contents: Data("时间,收支\n".utf8))
        let copy = try FileInbox.importableDataCopy(of: external)
        XCTAssertTrue(copy.path.hasPrefix(FileInbox.documents.path))
        XCTAssertEqual(try Data(contentsOf: copy), Data("时间,收支\n".utf8))
        FileInbox.consume(copy)
    }

    func testConsumeOnlyTouchesContainerFiles() throws {
        let external = try write("别删我.csv", contents: Data("x\n".utf8))
        FileInbox.consume(external)
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }

    func testBackupTypeDeclaredInInfoPlist() throws {
        // ledgerbak 必须在 Info.plist 里声明成自有类型：
        // 只靠 public.data 兜底时，系统拿到的是动态 UTI，
        // 分享面板/选择器都可能把它当成未知文件，表现就是「点了没反应」。
        let main = Bundle.main
        let exported = main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]]
        guard let exported else {
            throw XCTSkip("测试宿主不是应用本体，读不到应用的 Info.plist")
        }
        let extensions = exported
            .compactMap { ($0["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String] }
            .flatMap { $0 }
        XCTAssertTrue(extensions.contains(BackupService.encryptedExtension))

        let documentTypes = main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]]
        let identifiers = documentTypes?.compactMap { $0["LSItemContentTypes"] as? [String] }.flatMap { $0 } ?? []
        XCTAssertTrue(identifiers.contains("com.example.ledger.backup"))
    }
}
