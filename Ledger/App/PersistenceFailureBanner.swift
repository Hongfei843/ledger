import SwiftUI

/// 顶层「写入失败」提示条。
///
/// 自己订阅通知、自己管显示时长，根视图只挂一个 modifier——
/// 之前把这段直接写进 RootTabView 的 body 链里，编译器的类型推断直接超时了。
struct PersistenceFailureBanner: ViewModifier {
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(message)
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.danger.opacity(0.28), lineWidth: 0.8)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.88), value: message)
            .onReceive(NotificationCenter.default.publisher(for: PersistenceFailureCenter.didFail)) { note in
                present(note)
            }
    }

    private func present(_ note: Notification) {
        let action = note.userInfo?[PersistenceFailureCenter.actionKey] as? String ?? "改动"
        let reason = note.userInfo?[PersistenceFailureCenter.reasonKey] as? String ?? ""
        let headline = "「\(action)」没保存成功，已撤销这次改动"
        let full = reason.isEmpty ? headline : "\(headline)\n\(reason)"
        Haptics.warning()
        withAnimation { message = full }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            // 只清自己这一条，避免把随后又冒出来的新提示一起抹掉
            if message == full {
                withAnimation { message = nil }
            }
        }
    }
}

extension View {
    /// 挂上「写入失败」提示条
    func persistenceFailureBanner() -> some View {
        modifier(PersistenceFailureBanner())
    }
}
