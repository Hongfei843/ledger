import SwiftUI

/// 分享 / 「用其他应用打开」进来的两个弹窗入口。
///
/// 拆成独立 ViewModifier 不只为可读：根视图 body 已经很长，
/// 再往里堆 sheet 会踩到编译器「unable to type-check this expression in reasonable time」。
struct SharedFileSheets: ViewModifier {
    @Binding var csvFile: SharedFile?
    @Binding var backupFile: SharedFile?

    func body(content: Content) -> some View {
        content
            .sheet(item: $csvFile) { file in
                NavigationStack {
                    ImportView(initialFileURL: file.url)
                }
            }
            .sheet(item: $backupFile) { file in
                NavigationStack {
                    BackupRestoreView(initialFileURL: file.url)
                }
            }
    }
}

extension View {
    func sharedFileSheets(csv: Binding<SharedFile?>, backup: Binding<SharedFile?>) -> some View {
        modifier(SharedFileSheets(csvFile: csv, backupFile: backup))
    }
}

/// 收到但还没被用户确认的文件
struct IncomingFile: Identifiable {
    let id = UUID()
    let url: URL
    let kind: InboxFileKind
}

/// 收到文件后的顶部提示条。
///
/// 存在的理由很具体：从「文件」App 或分享面板拉起 App 时，自动弹的 sheet 常被系统吞掉，
/// 用户看到的只有「点了一下，什么也没发生」。提示条是普通视图，只要 App 起来了就渲染得出来。
struct IncomingFileBanner: View {
    let fileName: String
    let subtitle: String
    let actionTitle: String
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Button(actionTitle, action: onAction)
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 16)
    }
}
