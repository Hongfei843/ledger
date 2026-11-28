import XCTest
import SwiftData
import CryptoKit
@testable import Ledger

final class BackupCryptoTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    @MainActor
    private func makeContext() -> ModelContext {
        let container = ModelContainerFactory.preview()
        self.container = container
        return container.mainContext
    }

    private func emptyBackup() -> LedgerBackup {
        LedgerBackup(
            formatVersion: BackupService.formatVersion,
            exportedAt: Date(),
            books: [], accounts: [], categories: [], txns: [], claims: [], loans: [],
            scheduleItems: [], statements: [], reconciliationRuns: [], debts: [],
            merchantRules: [], captureRecords: [], recurringRules: [], quickTemplates: []
        )
    }

    /// 测试里把 PBKDF2 轮数压到 1000：正式环境是 21 万轮，慢在预期内，测试没必要陪着等。
    private let testRounds = 1_000

    func testSealAndOpenRoundTrip() throws {
        let plaintext = try BackupService.encode(emptyBackup())
        let counts = BackupCounts(backup: emptyBackup())

        let envelope = try BackupCrypto.seal(
            plaintext,
            passphrase: "正确的口令 1234",
            counts: counts,
            summary: "空备份",
            rounds: testRounds
        )

        XCTAssertEqual(envelope.format, "ledger-encrypted-backup")
        XCTAssertEqual(envelope.kdf.alg, "PBKDF2-HMAC-SHA256")
        XCTAssertEqual(envelope.cipher.alg, "AES-GCM-256")
        XCTAssertEqual(envelope.kdf.rounds, testRounds)

        let opened = try BackupCrypto.open(envelope, passphrase: "正确的口令 1234")
        XCTAssertEqual(opened, plaintext)
        XCTAssertEqual(
            Self.sha256Hex(opened),
            envelope.payloadSHA256,
            "解密后应能对上明文指纹"
        )
    }

    func testWrongPassphraseIsRejected() throws {
        let plaintext = try BackupService.encode(emptyBackup())
        let envelope = try BackupCrypto.seal(
            plaintext,
            passphrase: "first-pass",
            counts: BackupCounts(backup: emptyBackup()),
            summary: "空备份",
            rounds: testRounds
        )

        XCTAssertThrowsError(try BackupCrypto.open(envelope, passphrase: "second-pass")) { error in
            guard let cryptoError = error as? BackupCryptoError,
                  case .wrongPassphraseOrCorrupted = cryptoError else {
                return XCTFail("口令错误应报 wrongPassphraseOrCorrupted，实际：\(error)")
            }
        }
    }

    func testTamperedCiphertextIsRejected() throws {
        let plaintext = try BackupService.encode(emptyBackup())
        let envelope = try BackupCrypto.seal(
            plaintext,
            passphrase: "tamper-test",
            counts: BackupCounts(backup: emptyBackup()),
            summary: "空备份",
            rounds: testRounds
        )

        // 序列化后改密文里的一个字节，模拟文件被改动
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupService.encodeEnvelope(envelope)) as? [String: Any])
        var cipher = try XCTUnwrap(object["cipher"] as? [String: Any])
        var bytes = try XCTUnwrap(Data(base64Encoded: (cipher["data"] as? String) ?? ""))
        bytes[0] = bytes[0] ^ 0xFF
        cipher["data"] = bytes.base64EncodedString()
        object["cipher"] = cipher

        let tamperedData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let tampered = try decoder.decode(BackupEnvelope.self, from: tamperedData)

        XCTAssertThrowsError(try BackupCrypto.open(tampered, passphrase: "tamper-test"))
    }

    func testShortPassphraseIsRejectedBeforeDoingWork() {
        XCTAssertThrowsError(try BackupCrypto.seal(
            Data("{}".utf8),
            passphrase: "123",
            counts: BackupCounts(backup: emptyBackup()),
            summary: "空备份"
        )) { error in
            guard let cryptoError = error as? BackupCryptoError,
                  case .passphraseTooShort(let minimum) = cryptoError else {
                return XCTFail("短口令应被拒绝，实际：\(error)")
            }
            XCTAssertEqual(minimum, BackupCrypto.minimumPassphraseLength)
        }
    }

    func testDefaultRoundsAreTheProductionValue() throws {
        let envelope = try BackupCrypto.seal(
            Data("{}".utf8),
            passphrase: "default-round-check",
            counts: BackupCounts(backup: emptyBackup()),
            summary: "空备份"
        )
        // 只核对写进文件的参数，不解密（21 万轮在测试机上要跑一会儿）
        XCTAssertEqual(envelope.kdf.rounds, 210_000)
        XCTAssertEqual(envelope.kdf.salt.count, 16)
    }

    func testPlaintextBackupStillDecodesAndEnvelopeIsDetected() throws {
        let backup = emptyBackup()
        let plaintext = try BackupService.encode(backup)

        XCTAssertNil(BackupCrypto.envelope(in: plaintext), "明文备份不应被识别成加密信封")
        XCTAssertEqual(try BackupService.decode(plaintext).formatVersion, BackupService.formatVersion)

        let envelope = try BackupCrypto.seal(
            plaintext,
            passphrase: "兼容性测试口令",
            counts: BackupCounts(backup: backup),
            summary: "空备份",
            rounds: testRounds
        )
        let encrypted = try BackupService.encodeEnvelope(envelope)

        let detected = try XCTUnwrap(BackupCrypto.envelope(in: encrypted))
        XCTAssertEqual(detected.envelopeVersion, BackupCrypto.envelopeVersion)

        // 不给口令时必须明确报「需要口令」，而不是含糊的格式错误
        XCTAssertThrowsError(try BackupService.decodeDetailed(encrypted)) { error in
            guard let backupError = error as? BackupError,
                  case .encryptedNeedsPassphrase = backupError else {
                return XCTFail("应报 encryptedNeedsPassphrase，实际：\(error)")
            }
        }
        let decoded = try BackupService.decodeDetailed(encrypted, passphrase: "兼容性测试口令")
        XCTAssertTrue(decoded.isEncrypted)
        XCTAssertEqual(decoded.backup.exportedAt.timeIntervalSince1970,
                       backup.exportedAt.timeIntervalSince1970, accuracy: 1)
    }

    @MainActor
    func testExportWritesFileThatCanBeVerified() throws {
        let context = makeContext()
        let book = Book(name: "日常")
        let account = Account(bookId: book.id, name: "现金", type: .cash)
        let txn = Txn(bookId: book.id, type: .expense, amountMinor: 1_000, accountId: account.id)
        context.insert(book)
        context.insert(account)
        context.insert(txn)
        try context.save()

        let backup = try BackupService.makeBackup(context: context)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("crypto-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 生产路径用默认 21 万轮，这里只跑一次，确认「写出来 → 读回来 → 解开」闭环
        let url = try BackupService.writeFile(backup, passphrase: "导出自检pass", directory: dir)
        XCTAssertEqual(url.pathExtension, BackupService.encryptedExtension)

        let verified = try BackupService.verifyEncryptedFile(at: url, passphrase: "导出自检pass")
        XCTAssertEqual(verified.txns.count, 1)

        XCTAssertThrowsError(try BackupService.verifyEncryptedFile(at: url, passphrase: "错误的pass"))
    }

    @MainActor
    func testPersistenceGuardSavesAndReportsSuccess() throws {
        let context = makeContext()
        context.insert(Book(name: "守卫测试"))
        XCTAssertTrue(PersistenceGuard.save(context, "单元测试"))
        let books = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.count, 1)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}
