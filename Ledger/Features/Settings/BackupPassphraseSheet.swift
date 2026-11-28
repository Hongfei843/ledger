import SwiftUI

/// 备份口令输入面板：导出时设口令、导入时解锁。
/// 口令不落任何存储——写进 UserDefaults 或钥匙串，等于把「加密」降级成「藏起来」。
struct BackupPassphraseSheet: View {
    enum Mode {
        case createBackup
        case unlockBackup
    }

    let mode: Mode
    let headline: String
    let detail: String
    var errorMessage: String?
    var isWorking = false

    let onCancel: () -> Void
    let onSubmit: (String) -> Void

    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var reveal = false
    @FocusState private var focusedField: Field?

    private enum Field { case passphrase, confirmation }

    private var trimmed: String {
        passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var minimumLength: Int { BackupCrypto.minimumPassphraseLength }

    private var canSubmit: Bool {
        guard !isWorking else { return false }
        switch mode {
        case .createBackup:
            return trimmed.count >= minimumLength
                && trimmed == confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        case .unlockBackup:
            return !trimmed.isEmpty
        }
    }

    private var strengthHint: String {
        let length = trimmed.count
        if length == 0 { return "" }
        if length < minimumLength { return "至少 \(minimumLength) 位" }
        if length < 10 { return "够用了，再加长一点更稳" }
        return "这个长度已经很难被猜到"
    }

    private var strengthColor: Color {
        if trimmed.isEmpty { return .secondary }
        if trimmed.count < minimumLength { return Theme.danger }
        if trimmed.count < 10 { return .secondary }
        return Theme.accent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Group {
                            if reveal {
                                TextField(mode == .createBackup ? "设置备份口令" : "输入备份口令", text: $passphrase)
                            } else {
                                SecureField(mode == .createBackup ? "设置备份口令" : "输入备份口令", text: $passphrase)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .passphrase)
                        .submitLabel(mode == .createBackup ? .next : .done)

                        Button {
                            reveal.toggle()
                        } label: {
                            Image(systemName: reveal ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(reveal ? "隐藏口令" : "显示口令")
                    }

                    if mode == .createBackup {
                        Group {
                            if reveal {
                                TextField("再输一次", text: $confirmation)
                            } else {
                                SecureField("再输一次", text: $confirmation)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .confirmation)
                        .submitLabel(.done)
                    }
                } header: {
                    Text(headline)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !detail.isEmpty {
                            Text(detail)
                        }
                        if !strengthHint.isEmpty {
                            Text(strengthHint).foregroundStyle(strengthColor)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Text("口令不保存在 App 里，也不会写进备份文件。忘掉口令＝这份备份永久打不开，请自己记牢或用密码管理器存一份。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(mode == .createBackup ? "设置备份口令" : "解锁备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .createBackup ? "导出" : "解锁") {
                        onSubmit(trimmed)
                    }
                    .disabled(!canSubmit)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    focusedField = .passphrase
                }
            }
        }
    }
}
