import Foundation
import SwiftData

/// 截图识别记录，用于后续评估与规则迭代。
@Model
final class CaptureRecord {
    @Attribute(.unique) var id: UUID
    var imagePath: String?
    var ocrText: String
    var parsedAmountMinor: Int64?
    var parsedPayee: String?
    var parsedAccountId: UUID?
    var parsedCategoryId: UUID?
    var confidence: Double
    var isAccepted: Bool
    var sourceType: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(ocrText: String, sourceType: String = "other") {
        self.id = UUID()
        self.imagePath = nil
        self.ocrText = ocrText
        self.parsedAmountMinor = nil
        self.parsedPayee = nil
        self.parsedAccountId = nil
        self.parsedCategoryId = nil
        self.confidence = 0
        self.isAccepted = false
        self.sourceType = sourceType
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }
}
