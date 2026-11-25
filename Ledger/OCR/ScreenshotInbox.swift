import Foundation
import UIKit

/// 快捷指令把截图「存储到文件」到轻账目录（App 的 Documents），
/// 这里负责找最新一张、交给 OCR，并在成功导入后删掉，避免重复吃同一张图。
enum ScreenshotInbox {
    static let maxAge: TimeInterval = 180
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif"]

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// 最近 maxAge 秒内最新的一张图片；目录可注入，方便单测。
    static func latestImage(
        in directory: URL = ScreenshotInbox.documentsDirectory,
        maxAge: TimeInterval = ScreenshotInbox.maxAge,
        now: Date = Date()
    ) -> (url: URL, image: UIImage)? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, modified: Date)?
        for case let url as URL in enumerator {
            guard isImageFile(url),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) <= maxAge else { continue }
            if newest == nil || modified > newest!.modified {
                newest = (url, modified)
            }
        }

        guard let newest, let image = UIImage(contentsOfFile: newest.url.path) else { return nil }
        return (newest.url, image)
    }

    static func consume(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
