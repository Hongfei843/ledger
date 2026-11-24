import Foundation
import UIKit

/// 报销月报 PDF：A4 单页，可直接发领导。
enum ClaimReportPDF {
    static func make(_ report: ClaimMonthlyReport) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacing: CGFloat = 6) {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: pageRect.width - margin * 2, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin],
                    attributes: attributes,
                    context: nil
                )
                if y + bounding.height > pageRect.height - margin {
                    context.beginPage()
                    y = margin
                }
                (text as NSString).draw(
                    with: CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: bounding.height),
                    options: [.usesLineFragmentOrigin],
                    attributes: attributes,
                    context: nil
                )
                y += bounding.height + spacing
            }

            draw("报销月报 \(report.monthKey)", font: .boldSystemFont(ofSize: 22), spacing: 14)
            draw(
                "生成时间 \(DateFormatter.ledgerDateTime.string(from: Date()))",
                font: .systemFont(ofSize: 10),
                color: .gray,
                spacing: 16
            )

            draw("汇总", font: .boldSystemFont(ofSize: 15), spacing: 8)
            draw("本月垫付：\(report.advanceCount) 笔，合计 \(Money.format(report.advanceMinor))", font: .systemFont(ofSize: 12))
            draw("已提交：\(Money.format(report.submittedMinor))", font: .systemFont(ofSize: 12))
            draw("已到账：\(Money.format(report.receivedMinor))", font: .systemFont(ofSize: 12))
            draw("未到账余额：\(Money.format(report.outstandingMinor))", font: .systemFont(ofSize: 12))
            if let averageDays = report.averageDays {
                draw("平均回款天数：\(averageDays) 天", font: .systemFont(ofSize: 12))
            }
            y += 10

            if !report.categoryTotals.isEmpty {
                draw("按分类小计", font: .boldSystemFont(ofSize: 15), spacing: 8)
                for item in report.categoryTotals {
                    draw("· \(item.0)：\(Money.format(item.1))", font: .systemFont(ofSize: 12), spacing: 4)
                }
                y += 10
            }

            if !report.claims.isEmpty {
                draw("报销单明细", font: .boldSystemFont(ofSize: 15), spacing: 8)
                for claim in report.claims {
                    let daysText = claim.days.map { "，\($0) 天回款" } ?? ""
                    draw(
                        "\(claim.title)　\(claim.count) 笔　\(Money.format(claim.totalMinor))　[\(claim.status.displayName)]\(daysText)",
                        font: .systemFont(ofSize: 12),
                        spacing: 4
                    )
                }
                y += 10
            }

            if !report.overdueItems.isEmpty {
                draw("超期未提交（超过 45 天）", font: .boldSystemFont(ofSize: 15), color: .systemOrange, spacing: 8)
                for txn in report.overdueItems {
                    draw(
                        "\(DateFormatter.ledgerShort.string(from: txn.occurredAt))　\(Money.format(txn.amountMinor))　\(txn.note ?? "")",
                        font: .systemFont(ofSize: 12),
                        spacing: 4
                    )
                }
            }
        }
    }
}
