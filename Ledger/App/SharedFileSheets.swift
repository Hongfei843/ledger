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
