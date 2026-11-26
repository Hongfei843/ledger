import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 完整备份与恢复：备份文件是 JSON，恢复会覆盖当前数据（恢复前自动留副本）。
struct BackupRestoreView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var txns: [Txn]
    @Query private var loans: [Loan]

    @AppStorage(BackupService.lastBackupKey) private var lastBackupTimestamp: Double = 0
    @AppStorage(BackupService.lastRestoreKey) private var lastRestoreTimestamp: Double = 0

    @State private var backupFileURL: URL?
    @State private var showImporter = false
    @State private var pendingBackup: LedgerBackup?
    @State private var pendingFileName = ""
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
                    exportBackup()
                } label: {
                    Label(isWorking ? "处理中…" : "生成完整备份", systemImage: "externaldrive.badge.timemachine")
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
                Text("备份包含账户、分类、流水、报销、贷款与还款计划、信用卡账单、借入借出、周期记账、常用组合、商户规则等全部数据，可换机或重装后恢复。")
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
                Text("恢复会覆盖当前全部数据。恢复前会自动把当前数据另存一份到 App 的「文件 → 轻账 → AutoBackup」目录。")
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("确认恢复？", isPresented: Binding(
            get: { pendingBackup != nil },
            set: { if !$0 { pendingBackup = nil } }
        )) {
            Button("取消", role: .cancel) { pendingBackup = nil }
            Button("恢复", role: .destructive) { performRestore() }
        } message: {
            Text("将用「\(pendingFileName)」覆盖当前全部数据。\n\n备份内容：\(pendingSummaryText)")
        }
    }

    private func exportBackup() {
        isWorking = true
        defer { isWorking = false }
        do {
            let backup = try BackupService.makeBackup(context: context)
            let counts = BackupCounts(backup: backup)
            guard counts.total > 0 else {
                errorMessage = "当前没有可备份的数据。"
                return
            }
            backupFileURL = try BackupService.writeFile(backup)
            lastBackupTimestamp = Date().timeIntervalSince1970
            message = "已生成备份：\(counts.summaryText)"
            errorMessage = nil
            Haptics.success()
        } catch {
            errorMessage = "生成备份失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let backup = try BackupService.decode(data)
            pendingBackup = backup
            pendingFileName = url.lastPathComponent
            message = nil
            errorMessage = nil
        } catch {
            errorMessage = "读取备份失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }

    private func performRestore() {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try BackupService.restore(backup, into: context)
            lastRestoreTimestamp = Date().timeIntervalSince1970
            message = "恢复完成：\(result.counts.summaryText)"
            errorMessage = nil
            Haptics.success()
        } catch {
            errorMessage = "恢复失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }
}
