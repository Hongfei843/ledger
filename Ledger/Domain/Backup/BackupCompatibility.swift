import Foundation

/// 备份解码结果：带上格式版本与是否为旧版格式，便于 UI 提示。
struct BackupDecodeResult {
    let backup: LedgerBackup
    let version: Int
    let isLegacy: Bool
}

/// 旧版备份（AI 分析包里的 07-backup.json，schemaVersion = 1）兼容读取。
enum BackupCompatibility {
    static func decodeLegacyV1(_ data: Data) throws -> LedgerBackup {
        let legacy: LegacyBackupV1
        do {
            legacy = try JSONDecoder().decode(LegacyBackupV1.self, from: data)
        } catch {
            throw BackupError.invalidFormat
        }

        let book = Book(name: "导入账本")
        var accountDTOs: [AccountDTO] = []
        for item in legacy.accounts {
            guard let id = UUID(uuidString: item.id) else { continue }
            let account = Account(
                bookId: book.id,
                name: item.name,
                type: AccountType(rawValue: item.type) ?? .other,
                openingBalanceMinor: item.openingBalanceMinor ?? 0
            )
            account.id = id
            account.cachedBalanceMinor = item.cachedBalanceMinor ?? (item.openingBalanceMinor ?? 0)
            account.includeInNetWorth = item.includeInNetWorth ?? true
            account.isArchived = item.isArchived ?? false
            accountDTOs.append(AccountDTO(account))
        }
        if accountDTOs.isEmpty {
            let fallback = Account(bookId: book.id, name: "导入账户", type: .other)
            accountDTOs.append(AccountDTO(fallback))
        }

        var categoryDTOs: [CategoryDTO] = []
        for item in legacy.categories {
            guard let id = UUID(uuidString: item.id) else { continue }
            let category = Category(
                bookId: book.id,
                name: item.name,
                kind: CategoryKind(rawValue: item.kind) ?? .expense,
                iconEmoji: item.iconEmoji ?? "📦"
            )
            category.id = id
            categoryDTOs.append(CategoryDTO(category))
        }

        let accounts = accountDTOs
        var txnDTOs: [TxnDTO] = []
        for item in legacy.transactions {
            guard let id = UUID(uuidString: item.id) else { continue }
            let txn = Txn(
                bookId: book.id,
                type: TxnType(rawValue: item.type) ?? .expense,
                amountMinor: item.amountMinor,
                accountId: UUID(uuidString: item.accountId) ?? accounts[0].id,
                occurredAt: parseLegacyDate(item.occurredAt) ?? Date(),
                categoryId: item.categoryId.flatMap { UUID(uuidString: $0) },
                note: item.note,
                source: TxnSource(rawValue: item.source ?? "") ?? .imported
            )
            txn.id = id
            txn.isReimbursable = item.isReimbursable ?? false
            txn.refundOfTxnId = item.refundOfTxnId.flatMap { UUID(uuidString: $0) }
            txnDTOs.append(TxnDTO(txn))
        }

        return LedgerBackup(
            formatVersion: BackupService.formatVersion,
            exportedAt: parseLegacyDate(legacy.exportedAt ?? "") ?? Date(),
            books: [BookDTO(book)],
            accounts: accountDTOs,
            categories: categoryDTOs,
            txns: txnDTOs,
            claims: [],
            loans: [],
            scheduleItems: [],
            statements: [],
            reconciliationRuns: [],
            debts: [],
            merchantRules: [],
            captureRecords: [],
            recurringRules: [],
            quickTemplates: []
        )
    }

    private static func parseLegacyDate(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)
    }
}

// MARK: - 旧版 JSON 结构

private struct LegacyBackupV1: Decodable {
    var schemaVersion: Int?
    var exportedAt: String?
    var accounts: [LegacyAccount]
    var categories: [LegacyCategory]
    var transactions: [LegacyTransaction]

    struct LegacyAccount: Decodable {
        var id: String
        var name: String
        var type: String
        var openingBalanceMinor: Int64?
        var cachedBalanceMinor: Int64?
        var includeInNetWorth: Bool?
        var isArchived: Bool?
    }

    struct LegacyCategory: Decodable {
        var id: String
        var name: String
        var kind: String
        var iconEmoji: String?
    }

    struct LegacyTransaction: Decodable {
        var id: String
        var type: String
        var amountMinor: Int64
        var accountId: String
        var categoryId: String?
        var occurredAt: String
        var note: String?
        var isReimbursable: Bool?
        var refundOfTxnId: String?
        var source: String?
    }
}
