import Foundation
import UIKit

/// 截图 → 草稿：本地 OCR + 规则解析，不联网、不落原图。
enum ScreenshotImportService {
    static func makeDraft(from image: UIImage) async -> ScreenshotImportDraft {
        let lines = await OCRService.recognize(image)
        let parsed = ScreenshotParser.parse(lines: lines)
        return ScreenshotImportDraft(
            amountMinor: parsed.amountMinor,
            payee: parsed.payee,
            confidence: parsed.confidence,
            rawText: parsed.rawText
        )
    }

    static func makeDraft(fromImageData data: Data) async -> ScreenshotImportDraft? {
        guard let image = UIImage(data: data) else { return nil }
        return await makeDraft(from: image)
    }

    static func makeDraft(fromFileURL url: URL) async -> ScreenshotImportDraft? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return await makeDraft(fromImageData: data)
    }
}
