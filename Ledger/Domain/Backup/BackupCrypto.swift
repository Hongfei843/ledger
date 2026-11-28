import Foundation
import CryptoKit
import CommonCrypto
import Security

enum BackupCryptoError: LocalizedError, Equatable {
    case passphraseTooShort(minimum: Int)
    case keyDerivationFailed(Int32)
    case notEncrypted
    case wrongPassphraseOrCorrupted
    case unsupportedEnvelope(Int)

    var errorDescription: String? {
        switch self {
        case .passphraseTooShort(let minimum):
            return "备份口令至少 \(minimum) 位，短口令等于没加密。"
        case .keyDerivationFailed:
            return "口令派生密钥失败，请重试；如果反复失败，先换一个口令再导出。"
        case .notEncrypted:
            return "这个文件没有加密，可以用「从备份文件恢复」直接导入。"
        case .wrongPassphraseOrCorrupted:
            return "口令不正确，或文件已损坏。"
        case .unsupportedEnvelope(let version):
            return "这个加密备份的格式（v\(version)）当前版本还不支持。"
        }
    }
}

/// 加密备份信封。
///
/// 设计取舍：**用口令派生密钥，而不是把密钥存在 Keychain 里**。
/// 存 Keychain 的密钥绑在这台设备上，换机、重装、系统重置之后备份就打不开了——
/// 那等于备份只防「别人拿到文件」，防不住「你自己丢了手机」，对记账 App 是更坏的结果。
/// 口令是可带走的：只要记住它，任何一台设备都能恢复。
///
/// 信封外层只暴露条数与导出时间（够界面做「导入前预览」），
/// 真正的账目内容全部在 `cipher` 里，AES-GCM 自带完整性校验，改一个字节就打不开。
struct BackupEnvelope: Codable {
    struct KDF: Codable {
        var alg: String
        var rounds: Int
        var salt: Data
    }

    struct Cipher: Codable {
        var alg: String
        var nonce: Data
        var tag: Data
        var data: Data
    }

    var format: String
    var envelopeVersion: Int
    var exportedAt: Date
    /// 明文摘要，仅用于导入前预览，不含账目明细
    var summary: String
    var counts: BackupCounts
    var kdf: KDF
    var cipher: Cipher
    /// 明文的 SHA-256，解密后再核对一次，防止「能解开但内容被替换」
    var payloadSHA256: String
}

enum BackupCrypto {
    static let format = "ledger-encrypted-backup"
    static let envelopeVersion = 1
    static let kdfAlgorithm = "PBKDF2-HMAC-SHA256"
    static let cipherAlgorithm = "AES-GCM-256"
    /// 迭代次数：210000 是 OWASP 2023 对 PBKDF2-HMAC-SHA256 的建议下限。
    /// 真机上派生一次约 0.2–0.4 秒，导出/恢复时感知为「转了一下」，可以接受。
    static let defaultRounds = 210_000
    static let minimumPassphraseLength = 6

    // MARK: - 加密

    static func seal(
        _ plaintext: Data,
        passphrase: String,
        counts: BackupCounts,
        summary: String,
        exportedAt: Date = Date(),
        rounds: Int = defaultRounds
    ) throws -> BackupEnvelope {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumPassphraseLength else {
            throw BackupCryptoError.passphraseTooShort(minimum: minimumPassphraseLength)
        }

        var saltBytes = [UInt8](repeating: 0, count: 16)
        let saltStatus = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        guard saltStatus == errSecSuccess else {
            throw BackupCryptoError.keyDerivationFailed(Int(saltStatus))
        }
        let salt = Data(saltBytes)

        let key = try derivedKey(passphrase: trimmed, salt: salt, rounds: rounds)
        let sealed = AES.GCM.seal(plaintext, using: key)

        return BackupEnvelope(
            format: format,
            envelopeVersion: envelopeVersion,
            exportedAt: exportedAt,
            summary: summary,
            counts: counts,
            kdf: .init(alg: kdfAlgorithm, rounds: rounds, salt: salt),
            cipher: .init(
                alg: cipherAlgorithm,
                nonce: sealed.nonce.withUnsafeBytes { Data($0) },
                tag: sealed.tag,
                data: sealed.ciphertext
            ),
            payloadSHA256: SHA256.hash(data: plaintext).compactMap { String(format: "%02x", $0) }.joined()
        )
    }

    // MARK: - 解密

    static func open(_ envelope: BackupEnvelope, passphrase: String) throws -> Data {
        guard envelope.format == format else { throw BackupCryptoError.notEncrypted }
        guard envelope.envelopeVersion == envelopeVersion else {
            throw BackupCryptoError.unsupportedEnvelope(envelope.envelopeVersion)
        }
        guard envelope.kdf.alg == kdfAlgorithm, envelope.cipher.alg == cipherAlgorithm else {
            throw BackupCryptoError.unsupportedEnvelope(envelope.envelopeVersion)
        }
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BackupCryptoError.passphraseTooShort(minimum: minimumPassphraseLength)
        }

        let key = try derivedKey(passphrase: trimmed, salt: envelope.kdf.salt, rounds: envelope.kdf.rounds)
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: envelope.cipher.nonce),
            ciphertext: envelope.cipher.data,
            tag: envelope.cipher.tag
        )
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw BackupCryptoError.wrongPassphraseOrCorrupted
        }

        let digest = SHA256.hash(data: plaintext).compactMap { String(format: "%02x", $0) }.joined()
        guard digest == envelope.payloadSHA256 else {
            throw BackupCryptoError.wrongPassphraseOrCorrupted
        }
        return plaintext
    }

    // MARK: - 信封探测

    /// 只做结构判断，不碰密钥；用于「这个文件要不要输口令」。
    static func envelope(in data: Data) -> BackupEnvelope? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formatTag = object["format"] as? String,
              formatTag == BackupCrypto.format,
              let decoded = try? decoder.decode(BackupEnvelope.self, from: data) else {
            return nil
        }
        return decoded
    }

    // MARK: - 派生

    static func derivedKey(passphrase: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        var keyBytes = Data(count: 32)
        let status: Int32 = passphrase.withCString { password in
            keyBytes.withUnsafeMutableBytes { keyBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        password,
                        passphrase.utf8.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        keyBuffer.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        guard Int(status) == kCCSuccess else {
            throw BackupCryptoError.keyDerivationFailed(Int(status))
        }
        return SymmetricKey(data: keyBytes)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
