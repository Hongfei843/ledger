import Foundation
import SwiftData

/// 完整备份容器（v2）：包含全部本地数据，可无损恢复。
struct LedgerBackup: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var books: [BookDTO]
    var accounts: [AccountDTO]
    var categories: [CategoryDTO]
    var txns: [TxnDTO]
    var claims: [ClaimDTO]
    var loans: [LoanDTO]
    var scheduleItems: [LoanScheduleItemDTO]
    var statements: [StatementDTO]
    var reconciliationRuns: [ReconciliationRunDTO]
    var debts: [DebtDTO]
    var merchantRules: [MerchantRuleDTO]
    var captureRecords: [CaptureRecordDTO]
    var recurringRules: [RecurringRuleDTO]
    var quickTemplates: [QuickTemplateDTO]
}

/// 备份/恢复涉及的数据条数。
struct BackupCounts: Codable, Equatable {
    var books = 0
    var accounts = 0
    var categories = 0
    var txns = 0
    var claims = 0
    var loans = 0
    var scheduleItems = 0
    var statements = 0
    var reconciliationRuns = 0
    var debts = 0
    var merchantRules = 0
    var captureRecords = 0
    var recurringRules = 0
    var quickTemplates = 0

    init(backup: LedgerBackup) {
        books = backup.books.count
        accounts = backup.accounts.count
        categories = backup.categories.count
        txns = backup.txns.count
        claims = backup.claims.count
        loans = backup.loans.count
        scheduleItems = backup.scheduleItems.count
        statements = backup.statements.count
        reconciliationRuns = backup.reconciliationRuns.count
        debts = backup.debts.count
        merchantRules = backup.merchantRules.count
        captureRecords = backup.captureRecords.count
        recurringRules = backup.recurringRules.count
        quickTemplates = backup.quickTemplates.count
    }

    var total: Int {
        books + accounts + categories + txns + claims + loans + scheduleItems + statements
            + reconciliationRuns + debts + merchantRules + captureRecords + recurringRules + quickTemplates
    }

    /// 给用户看的一句话摘要
    var summaryText: String {
        var parts: [String] = []
        if accounts > 0 { parts.append("账户 \(accounts)") }
        if txns > 0 { parts.append("流水 \(txns)") }
        if categories > 0 { parts.append("分类 \(categories)") }
        if loans > 0 || scheduleItems > 0 { parts.append("贷款 \(loans)（\(scheduleItems) 期）") }
        if claims > 0 { parts.append("报销 \(claims)") }
        if statements > 0 { parts.append("账单 \(statements)") }
        if debts > 0 { parts.append("借入借出 \(debts)") }
        if recurringRules > 0 { parts.append("周期记账 \(recurringRules)") }
        if quickTemplates > 0 { parts.append("常用组合 \(quickTemplates)") }
        if parts.isEmpty { return "空备份" }
        return parts.joined(separator: " · ")
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidFormat
    case encryptedNeedsPassphrase
    case restoreRolledBack(underlying: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "备份格式版本 \(version) 与当前 App 不兼容，请升级 App 或重新导出备份。"
        case .invalidFormat:
            return "备份文件格式不正确，无法读取。"
        case .encryptedNeedsPassphrase:
            return "这是加密备份，需要输入导出时设置的口令。"
        case .restoreRolledBack(let underlying):
            return "恢复过程中写入失败，已把原数据写回，当前数据未改变。（\(underlying)）"
        }
    }
}

/// 完整备份与恢复。
///
/// 备份文件默认是**口令加密**的 `.ledgerbak`：口令经 PBKDF2-HMAC-SHA256（21 万轮）派生密钥，
/// 内容用 AES-GCM-256 加密，改一个字节都打不开；口令不存钥匙串、可跨设备带走。
/// 历史明文 `.json` 备份仍然能读（`decodeDetailed` 会按内容自动识别）。
enum BackupService {
    static let formatVersion = 2
    static let lastBackupKey = "backup.lastExportAt"
    static let lastRestoreKey = "backup.lastRestoreAt"
    /// 加密备份的扩展名；导入时同时允许 .ledgerbak / .json / 无扩展名（其它 App 转存常见）
    static let encryptedExtension = "ledgerbak"

    // MARK: - 导出

    @MainActor
    static func makeBackup(context: ModelContext, now: Date = Date()) throws -> LedgerBackup {
        LedgerBackup(
            formatVersion: formatVersion,
            exportedAt: now,
            books: try context.fetch(FetchDescriptor<Book>()).map(BookDTO.init),
            accounts: try context.fetch(FetchDescriptor<Account>()).map(AccountDTO.init),
            categories: try context.fetch(FetchDescriptor<Category>()).map(CategoryDTO.init),
            txns: try context.fetch(FetchDescriptor<Txn>()).map(TxnDTO.init),
            claims: try context.fetch(FetchDescriptor<Claim>()).map(ClaimDTO.init),
            loans: try context.fetch(FetchDescriptor<Loan>()).map(LoanDTO.init),
            scheduleItems: try context.fetch(FetchDescriptor<LoanScheduleItem>()).map(LoanScheduleItemDTO.init),
            statements: try context.fetch(FetchDescriptor<Statement>()).map(StatementDTO.init),
            reconciliationRuns: try context.fetch(FetchDescriptor<ReconciliationRun>()).map(ReconciliationRunDTO.init),
            debts: try context.fetch(FetchDescriptor<Debt>()).map(DebtDTO.init),
            merchantRules: try context.fetch(FetchDescriptor<MerchantRule>()).map(MerchantRuleDTO.init),
            captureRecords: try context.fetch(FetchDescriptor<CaptureRecord>()).map(CaptureRecordDTO.init),
            recurringRules: try context.fetch(FetchDescriptor<RecurringRule>()).map(RecurringRuleDTO.init),
            quickTemplates: try context.fetch(FetchDescriptor<QuickTemplate>()).map(QuickTemplateDTO.init)
        )
    }

    static func encode(_ backup: LedgerBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> LedgerBackup {
        try decodeDetailed(data).backup
    }

    /// 宽容解码：支持当前/更早格式、旧版（schemaVersion = 1）备份，以及加密信封。
    /// 传入 `passphrase` 才能解开加密备份；不给口令时对加密文件抛 `encryptedNeedsPassphrase`。
    static func decodeDetailed(_ data: Data, passphrase: String? = nil) throws -> BackupDecodeResult {
        if let envelope = BackupCrypto.envelope(in: data) {
            guard let passphrase, !passphrase.isEmpty else {
                throw BackupError.encryptedNeedsPassphrase
            }
            let plaintext = try BackupCrypto.open(envelope, passphrase: passphrase)
            var result = try decodeDetailed(plaintext)
            result.isEncrypted = true
            return result
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["formatVersion"] == nil,
           object["schemaVersion"] is Int {
            let legacy = try BackupCompatibility.decodeLegacyV1(data)
            return BackupDecodeResult(backup: legacy, version: 1, isLegacy: true)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: LedgerBackup
        do {
            backup = try decoder.decode(LedgerBackup.self, from: data)
        } catch {
            throw BackupError.invalidFormat
        }
        guard (1...formatVersion).contains(backup.formatVersion) else {
            throw BackupError.unsupportedVersion(backup.formatVersion)
        }
        return BackupDecodeResult(backup: backup, version: backup.formatVersion, isLegacy: false)
    }

    /// 生成临时加密备份文件，供 ShareLink 分享。
    static func writeFile(_ backup: LedgerBackup, passphrase: String, directory: URL? = nil, now: Date = Date()) throws -> URL {
        let folder = directory ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("轻账备份-\(fileNameStamp(now)).\(encryptedExtension)")
        let counts = BackupCounts(backup: backup)
        let envelope = try BackupCrypto.seal(
            encode(backup),
            passphrase: passphrase,
            counts: counts,
            summary: counts.summaryText,
            exportedAt: now
        )
        try encodeEnvelope(envelope).write(to: url, options: .atomic)
        return url
    }

    /// 明文备份（仅保留给兼容路径与测试用；界面一律走加密版本）。
    static func writeFile(_ backup: LedgerBackup, directory: URL? = nil, now: Date = Date()) throws -> URL {
        let folder = directory ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("轻账备份-\(fileNameStamp(now)).json")
        try encode(backup).write(to: url, options: .atomic)
        return url
    }

    static func encodeEnvelope(_ envelope: BackupEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    /// 导出后自检：把刚写出的文件读回来、解开、按真实 DTO 解析一遍。
    /// 只有这一步过了，界面才敢说「备份已生成」——否则可能交出去一个打不开的文件。
    static func verifyEncryptedFile(at url: URL, passphrase: String) throws -> LedgerBackup {
        let data = try Data(contentsOf: url)
        return try decodeDetailed(data, passphrase: passphrase).backup
    }

    // MARK: - 恢复

    /// 恢复备份：先删除全部本地数据，再写入备份内容。恢复前自动保存当前数据副本。
    ///
    /// 写入分两步落盘（清空 → 写入），任一步失败都不会留下「清空了但没写进去」的半截状态：
    /// 第一步失败直接抛错，数据仍在；第二步失败会把内存里的原数据副本原样写回再抛错。
    @MainActor
    @discardableResult
    static func restore(
        _ backup: LedgerBackup,
        into context: ModelContext,
        autoBackupDirectory: URL? = nil,
        passphrase: String? = nil
    ) throws -> (counts: BackupCounts, autoBackupURL: URL?) {
        // v1 与 v2 的 DTO 结构兼容，decodeDetailed 已做宽容升级；这里不能再把 v1 挡在恢复门外。
        guard (1...formatVersion).contains(backup.formatVersion) else {
            throw BackupError.unsupportedVersion(backup.formatVersion)
        }

        // 1) 先留副本：有口令就加密留，没有口令退化为明文（明文也比没有强）
        let currentBackup = try makeBackup(context: context)
        let autoBackupURL = try writeAutoBackupBeforeRestore(currentBackup, directory: autoBackupDirectory, passphrase: passphrase)

        // 2) 清空落盘：这一步失败等于什么都没做，数据仍然完整
        try deleteAll(in: context)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        // 3) 写入新数据：失败则把原数据写回，不留中间态
        do {
            insert(backup, into: context)
            try context.save()
        } catch {
            context.rollback()
            let recoveryError = recover(currentBackup, into: context)
            let underlying: String
            if let recoveryError {
                underlying = "\(error.localizedDescription)；写回原数据也失败了：\(recoveryError.localizedDescription)"
            } else {
                underlying = error.localizedDescription
            }
            throw BackupError.restoreRolledBack(underlying: underlying)
        }

        // 4) 恢复可能带来另一组账本 ID，立即修正当前账本，避免界面看起来像“数据消失”。
        let restoredBooks = try context.fetch(FetchDescriptor<Book>())
        let liveBooks = restoredBooks.filter { $0.deletedAt == nil }
        if let current = BookScope.currentId, liveBooks.contains(where: { $0.id == current }) {
            // 保留仍然有效的选择。
        } else {
            BookScope.setCurrent(liveBooks.first(where: { $0.isDefault })?.id ?? liveBooks.first?.id)
        }

        // 5) 用恢复后的数据重算账户余额缓存
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let txns = try context.fetch(FetchDescriptor<Txn>())
        BalanceService.refreshAll(accounts: accounts, transactions: txns)
        PersistenceGuard.save(context, "恢复后刷新余额")

        return (BackupCounts(backup: backup), autoBackupURL)
    }

    @MainActor
    private static func insert(_ backup: LedgerBackup, into context: ModelContext) {
        for dto in backup.books { context.insert(dto.makeModel()) }
        for dto in backup.accounts { context.insert(dto.makeModel()) }
        for dto in backup.categories { context.insert(dto.makeModel()) }
        for dto in backup.txns { context.insert(dto.makeModel()) }
        for dto in backup.claims { context.insert(dto.makeModel()) }
        for dto in backup.loans { context.insert(dto.makeModel()) }
        for dto in backup.scheduleItems { context.insert(dto.makeModel()) }
        for dto in backup.statements { context.insert(dto.makeModel()) }
        for dto in backup.reconciliationRuns { context.insert(dto.makeModel()) }
        for dto in backup.debts { context.insert(dto.makeModel()) }
        for dto in backup.merchantRules { context.insert(dto.makeModel()) }
        for dto in backup.captureRecords { context.insert(dto.makeModel()) }
        for dto in backup.recurringRules { context.insert(dto.makeModel()) }
        for dto in backup.quickTemplates { context.insert(dto.makeModel()) }

        if backup.books.isEmpty {
            context.insert(Book())
        }
    }

    /// 写入失败后的紧急写回：把恢复前的内存副本重新落盘。返回 nil 表示写回成功。
    @MainActor
    private static func recover(_ backup: LedgerBackup, into context: ModelContext) -> Error? {
        do {
            try deleteAll(in: context)
            insert(backup, into: context)
            try context.save()
            return nil
        } catch {
            return error
        }
    }

    @MainActor
    private static func writeAutoBackupBeforeRestore(_ current: LedgerBackup, directory: URL?, passphrase: String?) throws -> URL? {
        guard current.accounts.count + current.txns.count + current.categories.count > 0 else { return nil }

        let folder = directory ?? autoBackupFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        if let passphrase, !passphrase.isEmpty {
            let name = "恢复前自动备份-\(fileNameStamp(Date())).\(encryptedExtension)"
            let counts = BackupCounts(backup: current)
            let envelope = try BackupCrypto.seal(
                encode(current),
                passphrase: passphrase,
                counts: counts,
                summary: counts.summaryText
            )
            let url = folder.appendingPathComponent(name)
            try encodeEnvelope(envelope).write(to: url, options: .atomic)
            return url
        }

        let url = folder.appendingPathComponent("恢复前自动备份-\(fileNameStamp(Date())).json")
        try encode(current).write(to: url, options: .atomic)
        return url
    }

    static func autoBackupFolder() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("AutoBackup", isDirectory: true)
    }

    @MainActor
    private static func deleteAll(in context: ModelContext) throws {
        try context.delete(model: Txn.self)
        try context.delete(model: Account.self)
        try context.delete(model: Category.self)
        try context.delete(model: Book.self)
        try context.delete(model: Claim.self)
        try context.delete(model: Loan.self)
        try context.delete(model: LoanScheduleItem.self)
        try context.delete(model: Statement.self)
        try context.delete(model: ReconciliationRun.self)
        try context.delete(model: Debt.self)
        try context.delete(model: MerchantRule.self)
        try context.delete(model: CaptureRecord.self)
        try context.delete(model: RecurringRule.self)
        try context.delete(model: QuickTemplate.self)
    }

    private static func fileNameStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

// MARK: - DTO → 模型

extension BookDTO {
    func makeModel() -> Book {
        let model = Book(name: name, iconEmoji: iconEmoji, colorHex: colorHex, sortOrder: sortOrder, isDefault: isDefault)
        apply(to: model)
        return model
    }
}

extension AccountDTO {
    func makeModel() -> Account {
        let model = Account(
            bookId: bookId,
            name: name,
            type: AccountType(rawValue: typeRaw) ?? .other,
            openingBalanceMinor: openingBalanceMinor,
            iconEmoji: iconEmoji,
            colorHex: colorHex,
            sortOrder: sortOrder
        )
        apply(to: model)
        return model
    }
}

extension CategoryDTO {
    func makeModel() -> Category {
        let model = Category(
            bookId: bookId,
            name: name,
            kind: CategoryKind(rawValue: kindRaw) ?? .expense,
            parentId: parentId,
            iconEmoji: iconEmoji,
            colorHex: colorHex,
            sortOrder: sortOrder,
            defaultReimbursable: defaultReimbursable
        )
        apply(to: model)
        return model
    }
}

extension TxnDTO {
    func makeModel() -> Txn {
        let model = Txn(
            bookId: bookId,
            type: TxnType(rawValue: typeRaw) ?? .expense,
            amountMinor: amountMinor,
            accountId: accountId,
            occurredAt: occurredAt,
            categoryId: categoryId,
            counterAccountId: counterAccountId,
            payee: payee,
            note: note,
            source: TxnSource(rawValue: sourceRaw) ?? .manual
        )
        apply(to: model)
        return model
    }
}

extension ClaimDTO {
    func makeModel() -> Claim {
        let model = Claim(bookId: bookId, title: title, periodMonth: periodMonth)
        apply(to: model)
        return model
    }
}

extension LoanDTO {
    func makeModel() -> Loan {
        let model = Loan(
            bookId: bookId,
            name: name,
            type: LoanType(rawValue: typeRaw) ?? .other,
            principalMinor: principalMinor,
            annualRateBp: annualRateBp,
            termMonths: termMonths,
            startDate: startDate,
            firstDueDate: firstDueDate,
            dueDay: dueDay,
            repaymentMethod: RepaymentMethod(rawValue: repaymentMethodRaw) ?? .equalInstallment,
            paymentAccountId: paymentAccountId
        )
        apply(to: model)
        return model
    }
}

extension LoanScheduleItemDTO {
    func makeModel() -> LoanScheduleItem {
        let model = LoanScheduleItem(
            loanId: loanId,
            periodIndex: periodIndex,
            dueDate: dueDate,
            principalMinor: principalMinor,
            interestMinor: interestMinor,
            feeMinor: feeMinor
        )
        apply(to: model)
        return model
    }
}

extension StatementDTO {
    func makeModel() -> Statement {
        let model = Statement(
            accountId: accountId,
            periodMonth: periodMonth,
            billAmountMinor: billAmountMinor,
            minimumPaymentMinor: minimumPaymentMinor,
            dueDate: dueDate
        )
        apply(to: model)
        return model
    }
}

extension ReconciliationRunDTO {
    func makeModel() -> ReconciliationRun {
        let model = ReconciliationRun(
            bookId: bookId,
            accountCount: accountCount,
            diffCount: diffCount,
            totalDiffMinor: totalDiffMinor
        )
        apply(to: model)
        return model
    }
}

extension DebtDTO {
    func makeModel() -> Debt {
        let model = Debt(
            bookId: bookId,
            direction: DebtDirection(rawValue: directionRaw) ?? .lend,
            counterparty: counterparty,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            dueDate: dueDate
        )
        apply(to: model)
        return model
    }
}

extension MerchantRuleDTO {
    func makeModel() -> MerchantRule {
        let model = MerchantRule(payeeKey: payeeKey, categoryId: categoryId)
        apply(to: model)
        return model
    }
}

extension CaptureRecordDTO {
    func makeModel() -> CaptureRecord {
        let model = CaptureRecord(ocrText: ocrText, sourceType: sourceType)
        apply(to: model)
        return model
    }
}

extension RecurringRuleDTO {
    func makeModel() -> RecurringRule {
        let model = RecurringRule(
            bookId: bookId,
            title: title,
            templateType: TxnType(rawValue: templateTypeRaw) ?? .expense,
            amountMinor: amountMinor,
            accountId: accountId,
            frequency: RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly,
            startDate: startDate
        )
        apply(to: model)
        return model
    }
}

extension QuickTemplateDTO {
    func makeModel() -> QuickTemplate {
        let model = QuickTemplate(
            bookId: bookId,
            name: name,
            type: TxnType(rawValue: typeRaw) ?? .expense,
            amountMinor: amountMinor,
            accountId: accountId,
            categoryId: categoryId,
            payee: payee,
            note: note,
            sortOrder: sortOrder
        )
        apply(to: model)
        return model
    }
}
