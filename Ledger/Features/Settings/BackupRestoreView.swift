import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 完整备份与恢复。
///
/// 备份默认加密（口令 → PBKDF2 → AES-GCM），导出后会立刻读回来解一遍再报成功，
/// 保证交到用户手里的文件是真能打开的；历史明文 JSON 备份仍可直接导入。
struct BackupRestoreView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var txns: [Txn]
    @Query private var loans: [Loan]

    @AppStorage(BackupService.lastBackupKey) private var lastBackupTimestamp: Double = 0
    @AppStorage(BackupService.lastRestoreKey) private var lastRestoreTimestamp: Double = 0

    @State private var backupFileURL: URL?
    @State private var showImporter = false
    @State private var showPassphraseSheet = false
    @State private var passphraseMode: BackupPassphraseSheet.Mode = .createBackup
    @State private var passphraseError: String?

    /// 待解锁的加密备份（口令对上之前先留在内存里）
    @State private var pendingEncryptedData: Data?
    @State private var pendingEncryptedFileName = ""
    @State private var pendingEnvelope: BackupEnvelope?

    @State private var pendingBackup: LedgerBackup?
    @State private var pendingFileName = ""
    @State private var pendingVersion = 2
    @State private var pendingIsLegacy = false
    @State private var pendingIsEncrypted = false
    @State private var pendingExportedAt: Date?
    /// 刚才解锁用的口令：恢复前自动留的副本也用它加密，避免在磁盘上重新落一份明文
    @State private var restorePassphrase: String?

    @State private var isWorking = false
    @State private var message: String?
    @State private var errorMessage: String?

    private var lastBackupText: String {
        guard lastBackupTimestamp > 0 else { return "还没有备份" }
        return Self.displayFormatter.string(from: Date(timeIntervalSince1970: lastBackupTimestamp))
    }

    private var lastRestoreText: String {
        guard lastRestoreTimestamp > 0 else { return "还没有恢复过" }
        return Self.displayFormatter.string(from: Date(timeIntervalSince1970: lastRestoreTimestamp))
    }

    private var pendingSummaryText: String {
        guard let pendingBackup else { return "" }
        return BackupCounts(backup: pendingBackup).summaryText
    }

    private var pendingMetaText: String {
        var parts = ["格式 v\(pendingVersion)"]
        if pendingIsLegacy {
            parts.append("旧版备份，已自动补齐缺失字段")
        }
        if pendingIsEncrypted {
            parts.append("已加密")
        }
        if let pendingExportedAt {
            parts.append("导出于 " + Self.displayFormatter.string(from: pendingExportedAt))
        }
        return parts.joined(separator: " · ")
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    var body: some View {
        Form {
            Section {
                LabeledContent("账户", value: "\(accounts.count)")
                LabeledContent("流水", value: "\(txns.count)")
                LabeledContent("贷款", value: "\(loans.count)")
                LabeledContent("上次备份", value: lastBackupText)
                LabeledContent("上次恢复", value: lastRestoreText)
            } header: {
                Text("当前数据")
            }

            Section {
                Button {
                    passphraseError = nil
                    passphraseMode = .createBackup
                    showPassphraseSheet = true
                } label: {
                    Label(isWorking ? "处理中…" : "生成加密备份", systemImage: "lock.doc")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isWorking)

                if let backupFileURL {
                    ShareLink(item: backupFileURL) {
                        Label("分享备份文件", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("备份")
            } footer: {
                Text("备份包含账户、分类、流水、报销、贷款与还款计划、信用卡账单、借入借出、周期记账、常用组合、商户规则等全部数据，可换机或重装后恢复。文件用口令加密，只输入一次口令、导完立刻自检能解开。")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("从备份文件恢复", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isWorking)
            } header: {
                Text("恢复")
            } footer: {
                Text("恢复会覆盖当前全部数据。恢复前会自动把当前数据另存一份到 App 的「文件 → 轻账 → AutoBackup」目录，副本同样用本次口令加密。")
            }

            if let message {
                Section {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importTypes) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showPassphraseSheet) {
            passphraseSheet
        }
        .alert("确认恢复？", isPresented: Binding(
            get: { pendingBackup != nil },
            set: { if !$0 { pendingBackup = nil } }
        )) {
            Button("取消", role: .cancel) { pendingBackup = nil }
            Button("恢复", role: .destructive) { performRestore() }
        } message: {
            Text("将用「\(pendingFileName)」覆盖当前全部数据。\n\n\(pendingMetaText)\n备份内容：\(pendingSummaryText)")
        }
    }

    private var importTypes: [UTType] {
        var types: [UTType] = [.json, .data]
        if let ledgerbak = UTType(filenameExtension: BackupService.encryptedExtension) {
            types.append(ledgerbak)
        }
        return types
    }

    @ViewBuilder
    private var passphraseSheet: some View {
        switch passphraseMode {
        case .createBackup:
            BackupPassphraseSheet(
                mode: .createBackup,
                headline: "给这份备份设一个口令",
                detail: "导出后文件是加密的，只有知道口令才能恢复。建议用一句只有你自己记得的话。",
                errorMessage: passphraseError,
                isWorking: isWorking,
                onCancel: { showPassphraseSheet = false },
                onSubmit: { passphrase in exportBackup(passphrase: passphrase) }
            )
        case .unlockBackup:
            BackupPassphraseSheet(
                mode: .unlockBackup,
                headline: "这份备份已加密",
                detail: unlockDetailText,
                errorMessage: passphraseError,
                isWorking: isWorking,
                onCancel: {
                    showPassphraseSheet = false
                    pendingEncryptedData = nil
                    pendingEnvelope = nil
                },
                onSubmit: { passphrase in unlockPending(passphrase: passphrase) }
            )
        }
    }

    private var unlockDetailText: String {
        guard let envelope = pendingEnvelope else { return "输入导出时设置的口令。" }
        var parts: [String] = []
        if !envelope.summary.isEmpty { parts.append("备份内容：\(envelope.summary)") }
        parts.append("导出时间：" + Self.displayFormatter.string(from: envelope.exportedAt))
        parts.append("文件：" + pendingEncryptedFileName)
        return parts.joined(separator: "\n")
    }

    // MARK: - 导出

    private func exportBackup(passphrase: String) {
        isWorking = true
        defer { isWorking = false }
        do {
            let backup = try BackupService.makeBackup(context: context)
            let counts = BackupCounts(backup: backup)
            guard counts.total > 0 else {
                passphraseError = "当前没有可备份的数据。"
                return
            }
            let url = try BackupService.writeFile(backup, passphrase: passphrase)
            // 自检：读回来、解开、按 DTO 解析一遍，确保交出去的文件能恢复
            _ = try BackupService.verifyEncryptedFile(at: url, passphrase: passphrase)

            backupFileURL = url
            lastBackupTimestamp = Date().timeIntervalSince1970
            message = "已生成加密备份并自检通过：\(counts.summaryText)"
            errorMessage = nil
            passphraseError = nil
            showPassphraseSheet = false
            Haptics.success()
        } catch {
            passphraseError = "生成失败：\(error.localizedDescription)"
            errorMessage = "生成备份失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }

    // MARK: - 导入

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            message = nil
            errorMessage = nil

            if let envelope = BackupCrypto.envelope(in: data) {
                pendingEncryptedData = data
                pendingEncryptedFileName = url.lastPathComponent
                pendingEnvelope = envelope
                passphraseError = nil
                passphraseMode = .unlockBackup
                showPassphraseSheet = true
            } else {
                let decoded = try BackupService.decodeDetailed(data)
                let fileName = url.lastPathComponent
                // fileImporter 正在收起，直接弹 alert 会被系统吞掉；等它落定再弹。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    apply(decoded, fileName: fileName, wasEncrypted: false)
                }
                message = "这是未加密的旧备份，可以直接恢复。建议恢复后立刻重新导出一份加密备份。"
            }
        } catch {
            errorMessage = "读取备份失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }

    private func unlockPending(passphrase: String) {
        guard let data = pendingEncryptedData else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let decoded = try BackupService.decodeDetailed(data, passphrase: passphrase)
            restorePassphrase = passphrase
            passphraseError = nil
            showPassphraseSheet = false
            pendingEncryptedData = nil
            pendingEnvelope = nil
            let fileName = pendingEncryptedFileName
            Haptics.success()
            // 先让口令面板收起来，再弹恢复确认，否则两个模态会互相抢占
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                apply(decoded, fileName: fileName, wasEncrypted: true)
            }
        } catch {
            passphraseError = error.localizedDescription
            Haptics.warning()
        }
    }

    private func apply(_ decoded: BackupDecodeResult, fileName: String, wasEncrypted: Bool) {
        pendingBackup = decoded.backup
        pendingFileName = fileName
        pendingVersion = decoded.version
        pendingIsLegacy = decoded.isLegacy
        pendingIsEncrypted = wasEncrypted || decoded.isEncrypted
        pendingExportedAt = decoded.backup.exportedAt
    }

    private func performRestore() {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try BackupService.restore(backup, into: context, passphrase: restorePassphrase)
            lastRestoreTimestamp = Date().timeIntervalSince1970
            message = "恢复完成：\(result.counts.summaryText)"
            if pendingIsLegacy {
                message = "旧版备份已转换并恢复：\(result.counts.summaryText)"
            }
            if let auto = result.autoBackupURL {
                message = (message ?? "") + "\n恢复前副本：\(auto.lastPathComponent)"
            }
            errorMessage = nil
            Haptics.success()
        } catch {
            errorMessage = "恢复失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }
}
