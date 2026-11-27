import SwiftUI
import SwiftData

struct ClaimReportView: View {
    @Query private var claims: [Claim]
    @Query private var allTxns: [Txn]
    @Query private var categories: [Category]

    @State private var monthAnchor = Date()
    @State private var csvURL: URL?
    @State private var pdfURL: URL?

    private var report: ClaimMonthlyReport {
        let bookId = BookScope.currentId
        return ClaimReportBuilder.build(
            monthAnchor: monthAnchor,
            claims: claims.filter { bookId == nil || $0.bookId == bookId },
            txns: allTxns.filter { bookId == nil || $0.bookId == bookId },
            categories: categories.filter { bookId == nil || $0.bookId == bookId }
        )
    }

    private var monthTitle: String {
        let comps = AppCalendar.gregorian.dateComponents([.year, .month], from: monthAnchor)
        return "\(comps.year ?? 0)年\(comps.month ?? 0)月"
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(monthTitle).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
            }

            Section("汇总") {
                LabeledContent("本月垫付", value: "\(report.advanceCount) 笔 · \(Money.format(report.advanceMinor))")
                LabeledContent("已提交", value: Money.format(report.submittedMinor))
                LabeledContent("已到账", value: Money.format(report.receivedMinor))
                LabeledContent("未到账余额", value: Money.format(report.outstandingMinor))
                if let averageDays = report.averageDays {
                    LabeledContent("平均回款", value: "\(averageDays) 天")
                }
            }

            if !report.categoryTotals.isEmpty {
                Section("按分类小计") {
                    ForEach(Array(report.categoryTotals.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.0)
                            Spacer()
                            Text(Money.format(item.1)).monospacedDigit()
                        }
                    }
                }
            }

            if !report.claims.isEmpty {
                Section("报销单明细") {
                    ForEach(report.claims) { claim in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(claim.title).font(.subheadline)
                                Spacer()
                                Text(claim.status.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("\(claim.count) 笔")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Money.format(claim.totalMinor))
                                    .font(.subheadline)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }

            if !report.overdueItems.isEmpty {
                Section("超期未提交（超过 45 天）") {
                    ForEach(report.overdueItems, id: \.id) { txn in
                        HStack {
                            Text(DateFormatter.ledgerShort.string(from: txn.occurredAt))
                                .font(.caption)
                            Text(txn.note ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(Money.format(txn.amountMinor))
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
                Button {
                    exportCSV()
                } label: {
                    Label("导出 CSV", systemImage: "tablecells")
                }
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("分享 CSV", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    exportPDF()
                } label: {
                    Label("导出 PDF", systemImage: "doc.richtext")
                }
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("分享 PDF", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text("PDF 是 A4 单页版式，可直接发给领导或存档。")
            }
        }
        .navigationTitle("报销月报")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shift(_ delta: Int) {
        if let next = AppCalendar.gregorian.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
            csvURL = nil
            pdfURL = nil
        }
    }

    private func exportCSV() {
        let text = ClaimReportBuilder.csv(report)
        let name = "报销月报-\(report.monthKey).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        // 带 BOM，Excel 打开中文不乱码
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        do {
            try data.write(to: url, options: .atomic)
            csvURL = url
            Haptics.success()
        } catch {
            Haptics.warning()
        }
    }

    private func exportPDF() {
        let data = ClaimReportPDF.make(report)
        let name = "报销月报-\(report.monthKey).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            pdfURL = url
            Haptics.success()
        } catch {
            Haptics.warning()
        }
    }
}
