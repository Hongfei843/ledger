import XCTest
import Foundation
import UIKit
@testable import Ledger

/// 截图识别草稿的存取、过期策略，以及「轻账」目录里收截图。
final class ScreenshotImportTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ledger.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeDraft(amount: Int64? = 2380, createdAt: Date = Date()) -> ScreenshotImportDraft {
        ScreenshotImportDraft(
            amountMinor: amount,
            payee: "星巴克",
            confidence: 0.75,
            rawText: "付款成功\n星巴克\n¥23.80",
            createdAt: createdAt
        )
    }

    func testStoreRoundTrip() {
        let draft = makeDraft()
        ScreenshotImportStore.save(draft, defaults: defaults)

        let pending = ScreenshotImportStore.pending(defaults: defaults)
        XCTAssertEqual(pending?.amountMinor, 2380)
        XCTAssertEqual(pending?.payee, "星巴克")
        XCTAssertEqual(pending?.confidence, 0.75)
    }

    func testTakeClearsPending() {
        ScreenshotImportStore.save(makeDraft(), defaults: defaults)

        XCTAssertNotNil(ScreenshotImportStore.take(defaults: defaults))
        XCTAssertNil(ScreenshotImportStore.take(defaults: defaults))
        XCTAssertNil(ScreenshotImportStore.pending(defaults: defaults))
    }

    func testStaleDraftIgnored() {
        let stale = makeDraft(createdAt: Date().addingTimeInterval(-20 * 60))
        ScreenshotImportStore.save(stale, defaults: defaults)

        XCTAssertNil(ScreenshotImportStore.pending(defaults: defaults))
        XCTAssertNil(defaults.data(forKey: ScreenshotImportStore.storageKey))
    }

    func testSavePostsNotification() {
        let expectation = expectation(forNotification: .screenshotImportReady, object: nil)
        ScreenshotImportStore.save(makeDraft(), defaults: defaults)
        wait(for: [expectation], timeout: 2)
    }

    func testRawTextTruncated() {
        let longText = String(repeating: "账单", count: 800)
        let draft = ScreenshotImportDraft(amountMinor: 100, payee: nil, confidence: 0.2, rawText: longText)
        XCTAssertEqual(draft.rawText.count, 600)
    }

    // MARK: - 轻账目录收截图

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-inbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 1x1 透明 PNG
    private let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func writeImage(named name: String, in directory: URL, modified: Date) throws {
        let url = directory.appendingPathComponent(name)
        try pngData.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func testInboxFindsLatestImage() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeImage(named: "old.png", in: dir, modified: Date().addingTimeInterval(-60))
        try writeImage(named: "new.png", in: dir, modified: Date())

        let found = ScreenshotInbox.latestImage(in: dir, maxAge: 180)
        XCTAssertEqual(found?.url.lastPathComponent, "new.png")
        XCTAssertNotNil(found?.image)
    }

    func testInboxIgnoresStaleAndNonImageFiles() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeImage(named: "stale.png", in: dir, modified: Date().addingTimeInterval(-3600))
        try "hello".data(using: .utf8)!.write(to: dir.appendingPathComponent("note.txt"))

        XCTAssertNil(ScreenshotInbox.latestImage(in: dir, maxAge: 180))
    }

    func testInboxConsumeDeletesFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeImage(named: "shot.png", in: dir, modified: Date())
        let found = try XCTUnwrap(ScreenshotInbox.latestImage(in: dir, maxAge: 180))

        ScreenshotInbox.consume(found.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: found.url.path))
    }

    func testImageFileDetection() {
        XCTAssertTrue(ScreenshotInbox.isImageFile(URL(fileURLWithPath: "/tmp/a.PNG")))
        XCTAssertTrue(ScreenshotInbox.isImageFile(URL(fileURLWithPath: "/tmp/a.heic")))
        XCTAssertFalse(ScreenshotInbox.isImageFile(URL(fileURLWithPath: "/tmp/a.csv")))
    }
}
