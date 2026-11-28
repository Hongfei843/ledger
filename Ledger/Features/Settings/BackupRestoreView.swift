import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 完整备份与恢复。
///
/// 备份默认加密（口令 → PBKDF2 → AES-GCM），导出后会立刻读回来解一遍再报成功，
/// 保证交到用户手里的文件是真能打开的；历史明文 JSON 备份仍可直接导入。
///
/// 文件进来的三条路都收在这里：系统选择器、App 收件箱（「文件 App → 我的 iPhone → 轻账 → 导入」）、
/// 以及「文件」App / 分享面板直接打开本应用。后两种一律先落成「刚收到的备份」卡片，
/// 等用户点一下再走口令与确认——不自动弹模态，避免模态抢占导致「看起来毫无反应」。
struct BackupRestoreView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
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

    /// 从系统分享 / 「文件」App 直接递进来的备份文件
    private let initialFileURL: URL?
    @State private var didLoadInitialFile = false
    @State private var inboxFiles: [InboxFile] = []

    /// 刚收到、等待用户确认的那份备份
    @State private var receivedURL: URL?
    @State private var receivedName = ""
    @State private var receivedData: Data?
    @State private var receivedEnvelope: BackupEnvelope?
    @State private var receivedDecoded: BackupDecodeResult?

    /// 待解锁的加密备份（口令对上之前先留在内存里）
    @State private var pendingEncryptedData: Data?
    @State private var pendingEncryptedFileName = ""
    @State private var pendingEnvelope: BackupEnvelope?
    /// 这次恢复读的文件（容器内的副本在恢复成功后清掉）
    @State private var pendingSourceURL: URL?

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

    init(initialFileURL: URL? = nil) {
        self.initialFileURL = initialFileURL
    }

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
            if receivedURL != nil {
                receivedSection
            }
            summarySection
            backupSection
            restoreSection
            if let message {
                Section {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                        .listRowSeparator(.hidden)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        // 悬浮 Tab 栏是 safeAreaInset，只压缩滚动安全区、不压缩页面本身；
        // 不给底部留白，最后一段说明就会被栏压住。
        .contentMargins(.bottom, Theme.Layout.tabBarHeight + 12, for: .scrollContent)
        .toolbar {
            if initialFileURL != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        // 不用 SwiftUI 的 .fileImporter：它在部分模态栈里会「弹出来却选不动」，
        // 而且默认按安全作用域给 URL。这里统一走 asCopy 的 UIDocumentPicker。
        .sheet(isPresented: $showImporter) {
            DocumentPicker(allowedTypes: [.item]) { url in
                showImporter = false
                handleImportURL(url)
            } onCancel: {
                showImporter = false
            }
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
        .onAppear { refreshInbox() }
        .task {
            guard !didLoadInitialFile else { return }
            didLoadInitialFile = true
            if let initialFileURL {
                handleImportURL(initialFileURL)
            }
        }
    }

    // MARK: - 页面分块

    /// 刚收到的备份：一行摘要 + 一个明确的动作按钮，避免「打开就弹密码框」被系统吞掉
    @ViewBuilder
    private var receivedSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(receivedName.isEmpty ? "备份文件" : receivedName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(receivedMetaText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .listRowSeparator(.hidden)

            Button {
                beginReceivedRestore()
            } label: {
                Label(receivedEnvelope == nil ? "确认恢复" : "输入口令并恢复", systemImage: "lock.open")
                    .frame(maxWidth: .infinity)
            }
            .listRowSeparator(.hidden)

            Button("忽略这份文件") { clearReceived() }
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
        } header: {
            Text("刚收到的备份")
        } footer: {
            Text("已复制到「轻账 → 导入」，不会动原文件。")
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            LabeledContent("账户", value: "\(accounts.count)")
                .listRowSeparator(.hidden)
            LabeledContent("流水", value: "\(txns.count)")
                .listRowSeparator(.hidden)
            if !loans.isEmpty {
                LabeledContent("贷款", value: "\(loans.count)")
                    .listRowSeparator(.hidden)
            }
            LabeledContent("上次备份", value: lastBackupText)
                .listRowSeparator(.hidden)
            LabeledContent("上次恢复", value: lastRestoreText)
                .listRowSeparator(.hidden)
        } header: {
            Text("当前数据")
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        Section {
            Button {
                passphraseError = nil
                passphraseMode = .createBackup
                showPassphraseSheet = true
            } label: {
                Label(isWorking ? "处理中…" : "生成加密备份", systemImage: "lock.doc")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .disabled(isWorking)
            .listRowBackground(Theme.accent.opacity(0.13))
            .listRowSeparator(.hidden)

            if let backupFileURL {
                ShareLink(item: backupFileURL) {
                    Label("分享备份文件", systemImage: "square.and.arrow.up")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .listRowSeparator(.hidden)
            }
        } header: {
            Text("备份")
        } footer: {
            Text("含账户、分类、流水、报销、贷款、账单、借入借出、周期记账等全部数据；文件用口令加密，导完立刻自检能解开。")
        }
    }

    /// 恢复入口：选择器 + App 收件箱，后者不依赖任何系统授权
    @ViewBuilder
    private var restoreSection: some View {
        Section {
            Button {
                showImporter = true
            } label: {
                Label("从备份文件恢复", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .disabled(isWorking)
            .listRowSeparator(.hidden)
        } header: {
            Text("恢复")
        } footer: {
            Text("恢复会覆盖当前全部数据；恢复前会自动把当前数据加密存一份到「轻账 → AutoBackup」。")
        }

        Section {
            if inboxFiles.isEmpty {
                Text("「轻账 → 导入」里还没有备份文件。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(inboxFiles) { file in
                    Button {
                        handleImportURL(file.url)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: file.kind.systemImage)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text("\(file.sizeText) · \(file.modifiedText)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
            }

            Button {
                refreshInbox()
            } label: {
                Label("刷新列表", systemImage: "arrow.clockwise")
                    .font(.footnote)
            }
            .listRowSeparator(.hidden)
        } header: {
            Text("轻账文件夹里的备份")
        } footer: {
            Text("把备份文件放进「文件 App → 我的 iPhone → 轻账 → 导入」，上面就会出现，点一下即可恢复，不经过系统选择器。")
        }
    }

    private var receivedMetaText: String {
        var parts: [String] = []
        if let envelope = receivedEnvelope {
            if !envelope.summary.isEmpty { parts.append(envelope.summary) }
            parts.append("导出于 " + Self.displayFormatter.string(from: envelope.exportedAt))
            parts.append("已加密")
        } else if let decoded = receivedDecoded {
            parts.append(BackupCounts(backup: decoded.backup).summaryText)
            parts.append("导出于 " + Self.displayFormatter.string(from: decoded.backup.exportedAt))
            parts.append("未加密")
        } else {
            parts.append("读取中…")
        }
        return parts.joined(separator: " · ")
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

    /// 所有入口的统一落点：先把文件读进「刚收到」卡片，再由用户点按钮推进。
    private func handleImportURL(_ url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            message = nil
            errorMessage = nil
            pendingSourceURL = url
            receivedURL = url
            receivedName = url.lastPathComponent
            receivedData = data
            receivedEnvelope = BackupCrypto.envelope(in: data)
            receivedDecoded = nil
            if receivedEnvelope == nil {
                receivedDecoded = try BackupService.decodeDetailed(data)
            }
            Haptics.tap()
        } catch {
            errorMessage = "读取备份失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }

    private func beginReceivedRestore() {
        guard let data = receivedData else { return }
        if let envelope = receivedEnvelope {
            pendingEncryptedData = data
            pendingEncryptedFileName = receivedName
            pendingEnvelope = envelope
            passphraseError = nil
            passphraseMode = .unlockBackup
            showPassphraseSheet = true
            return
        }

        if let decoded = receivedDecoded {
            let fileName = receivedName
            // 让选择器/分享面板先落定，再弹确认，避免两个模态互相抢占
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                apply(decoded, fileName: fileName, wasEncrypted: false)
            }
            message = "这是未加密的旧备份，可以直接恢复。建议恢复后立刻重新导出一份加密备份。"
        }
    }

    private func clearReceived() {
        receivedURL = nil
        receivedName = ""
        receivedData = nil
        receivedEnvelope = nil
        receivedDecoded = nil
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
            clearReceived()
            if let pendingSourceURL {
                FileInbox.consume(pendingSourceURL)
                self.pendingSourceURL = nil
                refreshInbox()
            }
        } catch {
            errorMessage = "恢复失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }

    private func refreshInbox() {
        inboxFiles = FileInbox.candidates(kind: .backup)
    }
}
