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

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "备份格式版本 \(version) 与当前 App 不兼容，请升级 App 或重新导出备份。"
        case .invalidFormat:
            return "备份文件格式不正确，无法读取。"
        }
    }
}

/// 完整备份与恢复。备份文件是带版本号的 JSON，恢复前会自动留下当前数据的副本。
enum BackupService {
    static let formatVersion = 2
    static let lastBackupKey = "backup.lastExportAt"
    static let lastRestoreKey = "backup.lastRestoreAt"

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

    /// 宽容解码：支持当前/更早格式，以及旧版（schemaVersion = 1）备份。
    static func decodeDetailed(_ data: Data) throws -> BackupDecodeResult {
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

    /// 生成临时备份文件，供 ShareLink 分享。
    static func writeFile(_ backup: LedgerBackup, directory: URL? = nil, now: Date = Date()) throws -> URL {
        let folder = directory ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("轻账备份-\(fileNameStamp(now)).json")
        try encode(backup).write(to: url, options: .atomic)
        return url
    }

    // MARK: - 恢复

    /// 恢复备份：先删除全部本地数据，再写入备份内容。恢复前自动保存当前数据副本。
    @MainActor
    @discardableResult
    static func restore(_ backup: LedgerBackup, into context: ModelContext, autoBackupDirectory: URL? = nil) throws -> (counts: BackupCounts, autoBackupURL: URL?) {
        // v1 与 v2 的 DTO 结构兼容，decodeDetailed 已做宽容升级；这里不能再把 v1 挡在恢复门外。
        guard (1...formatVersion).contains(backup.formatVersion) else {
            throw BackupError.unsupportedVersion(backup.formatVersion)
        }

        let autoBackupURL = try writeAutoBackupBeforeRestore(context: context, directory: autoBackupDirectory)

        try deleteAll(in: context)
        try context.save()

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

        try context.save()

        // 恢复可能带来另一组账本 ID，立即修正当前账本，避免界面看起来像“数据消失”。
        let restoredBooks = try context.fetch(FetchDescriptor<Book>())
        let liveBooks = restoredBooks.filter { $0.deletedAt == nil }
        if let current = BookScope.currentId, liveBooks.contains(where: { $0.id == current }) {
            // 保留仍然有效的选择。
        } else {
            BookScope.setCurrent(liveBooks.first(where: { $0.isDefault })?.id ?? liveBooks.first?.id)
        }

        // 用恢复后的数据重算账户余额缓存
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let txns = try context.fetch(FetchDescriptor<Txn>())
        BalanceService.refreshAll(accounts: accounts, transactions: txns)
        try context.save()

        return (BackupCounts(backup: backup), autoBackupURL)
    }

    @MainActor
    private static func writeAutoBackupBeforeRestore(context: ModelContext, directory: URL?) throws -> URL? {
        let current = try makeBackup(context: context)
        guard current.accounts.count + current.txns.count + current.categories.count > 0 else { return nil }

        let folder = directory ?? autoBackupFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
