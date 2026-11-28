import Foundation
import UniformTypeIdentifiers

/// 文件类型判定：只按扩展名，不看内容——内容解析交给各自的导入器。
enum InboxFileKind: String {
    case csv
    case backup
    case image
    case other

    var displayName: String {
        switch self {
        case .csv: return "账单 CSV"
        case .backup: return "备份文件"
        case .image: return "图片"
        case .other: return "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .csv: return "tablecells"
        case .backup: return "shippingbox"
        case .image: return "photo"
        case .other: return "doc"
        }
    }
}

struct InboxFile: Identifiable, Equatable {
    let url: URL
    let kind: InboxFileKind
    let size: Int
    let modified: Date

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var modifiedText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: modified)
    }
}

/// 「轻账」自己的文件入口。
///
/// 存在的理由：系统文件选择器在自签环境里并不可靠——
/// ① 存在 iCloud Drive 的文件，App 没有 iCloud entitlement 时会被置灰、点不动；
/// ② 微信 / QQ 这类别的 App 容器里的文件，系统往往只允许预览、不允许拷给第三方。
/// 这两条都不是改代码能绕过去的（都要付费账号拿 entitlement），所以 App 必须有一条
/// **完全不依赖选择器**的路：文件放进「我的 iPhone → 轻账 → 导入」，
/// 由 App 自己扫自己容器，必然可读。
enum FileInbox {
    /// 用户手动放文件的目录，在「文件」App 里显示为 轻账/导入
    static let importFolderName = "导入"

    /// App 容器根（文件 App 里的「轻账」）
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// 系统把「用其他应用打开」的文件投递到这里
    static var systemInbox: URL {
        documents.appendingPathComponent("Inbox", isDirectory: true)
    }

    @discardableResult
    static func ensureImportFolder() throws -> URL {
        let url = documents.appendingPathComponent(importFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func kind(of url: URL) -> InboxFileKind {
        switch url.pathExtension.lowercased() {
        case "csv", "tsv", "txt":
            return .csv
        case "ledgerbak", "json", "ledgerbackup", "bak":
            return .backup
        case "png", "jpg", "jpeg", "heic", "heif", "webp", "gif":
            return .image
        default:
            // 微信「另存为」偶尔会丢掉扩展名，这里用文件头兜底嗅探
            return sniffKind(of: url)
        }
    }

    /// 扫描 App 容器里所有「可当作导入源」的文件，最新在前。
    static func candidates() -> [InboxFile] {
        candidates(in: [documents, documents.appendingPathComponent(importFolderName, isDirectory: true), systemInbox])
    }

    /// 指定目录版本，便于单测用临时目录验证，不碰真实容器
    static func candidates(in directories: [URL]) -> [InboxFile] {
        var files: [InboxFile] = []

        for directory in directories {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in urls {
                guard isRegularFile(url), !isInternal(url) else { continue }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                files.append(
                    InboxFile(
                        url: url,
                        kind: kind(of: url),
                        size: values?.fileSize ?? 0,
                        modified: values?.contentModificationDate ?? .distantPast
                    )
                )
            }
        }

        return files.sorted { $0.modified > $1.modified }
    }

    static func candidates(kind: InboxFileKind) -> [InboxFile] {
        candidates().filter { $0.kind == kind }
    }

    /// 把外部（分享 / open-in-place / 选择器）给出的 URL 变成 App 容器内的副本。
    ///
    /// 外部 URL 的安全作用域只在回调期间有效，不复制就直接解析，
    /// 遇到 iCloud 未下载或跨容器文件会读不到——这正是「点了没反应」的来源之一。
    static func importableCopy(of url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // 已经在自己的容器里：系统投递的 Inbox 文件挪进「导入」里，位置固定、用户也看得见；
        // 其余原地返回，不重复拷贝。
        if url.path.hasPrefix(documents.path) {
            guard url.path.hasPrefix(systemInbox.path) else { return url }
            let folder = try ensureImportFolder()
            let name = uniqueName(for: url.lastPathComponent, in: folder)
            let destination = folder.appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: url, to: destination)
            } catch {
                try FileManager.default.copyItem(at: url, to: destination)
                try? FileManager.default.removeItem(at: url)
            }
            return destination
        }

        let folder = try ensureImportFolder()
        let name = uniqueName(for: url.lastPathComponent, in: folder)
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    /// 导入成功后删掉容器内的副本，避免同一份文件下次又被列出来。
    /// 容器外的文件一律不碰。
    static func consume(_ url: URL) {
        guard url.path.hasPrefix(documents.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 内部

    private static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile ?? false
    }

    /// 排除 App 自己生成的诊断/日志文件，别让它们混进「可导入」列表
    private static func isInternal(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix("写入失败日志") { return true }
        if name.hasPrefix("恢复前自动备份-") { return true }
        if url.path.contains("/AutoBackup/") { return true }
        return false
    }

    private static func uniqueName(for name: String, in folder: URL) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var index = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            index += 1
            if index > 100 { break }
        }
        return candidate
    }

    /// 无扩展名兜底：只看前 512 字节，够区分 JSON / CSV / 图片魔数
    private static func sniffKind(of url: URL) -> InboxFileKind {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .other }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 512)) ?? Data()
        guard !head.isEmpty else { return .other }

        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return .image }          // JPEG
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .image }    // PNG
        if let first = head.first, first == UInt8(ascii: "{") { return .backup }
        return .csv
    }
}
