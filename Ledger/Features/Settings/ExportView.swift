import SwiftUI
import SwiftData

struct ExportView: View {
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var allTxns: [Txn]
    @Query private var claims: [Claim]

    enum RangeOption: String, CaseIterable, Identifiable {
        case thisMonth
        case lastThreeMonths
        case thisYear
        case all

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .thisMonth: return "本月"
            case .lastThreeMonths: return "近 3 个月"
            case .thisYear: return "今年"
            case .all: return "全部"
            }
        }
    }

    @State private var rangeOption: RangeOption = .thisMonth
    @State private var redacted = true
    @State private var fileURL: URL?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var interval: DateInterval {
        let now = Date()
        switch rangeOption {
        case .thisMonth:
            return AppCalendar.monthInterval(containing: now)
        case .lastThreeMonths:
            let start = AppCalendar.gregorian.date(byAdding: .month, value: -2, to: AppCalendar.startOfMonth(now)) ?? now
            return DateInterval(start: start, end: AppCalendar.startOfNextMonth(now))
        case .thisYear:
            let calendar = AppCalendar.gregorian
            let comps = calendar.dateComponents([.year], from: now)
            let start = calendar.date(from: comps) ?? now
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? now
            return DateInterval(start: start, end: end)
        case .all:
            let earliest = allTxns.map { $0.occurredAt }.min() ?? now
            let latest = allTxns.map { $0.occurredAt }.max() ?? now
            return DateInterval(start: AppCalendar.startOfDay(earliest), end: AppCalendar.startOfDay(latest).addingTimeInterval(86400))
        }
    }

    private var recordCount: Int {
        allTxns.filter { $0.deletedAt == nil && interval.contains($0.occurredAt) }.count
    }

    var body: some View {
        Form {
            Section("时间范围") {
                Picker("范围", selection: $rangeOption) {
                    ForEach(RangeOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: rangeOption) { _, _ in fileURL = nil }
                LabeledContent("记录条数", value: "\(recordCount)")
            }

            Section {
                Toggle("脱敏导出", isOn: $redacted)
                    .onChange(of: redacted) { _, _ in fileURL = nil }
            } footer: {
                Text("开启后，商户名与备注替换为 ***、账户名替换为「账户1/2」，金额与分类保留。发给外部 AI 时建议开启。")
            }

            Section {
                if let fileURL {
                    ShareLink(item: fileURL) {
                        Label("分享分析包", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    generate()
                } label: {
                    Text(isWorking ? "生成中…" : (fileURL == nil ? "生成分析包" : "重新生成"))
                        .frame(maxWidth: .infinity)
                }
                .disabled(isWorking || recordCount == 0)
            } footer: {
                Text("压缩包含：摘要（Markdown）、结构化 JSON、明细 CSV、月度/分类/账户汇总，以及完整备份。")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .ledgerTabBarClearance()
        .navigationTitle("导出分析包")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generate() {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try AIExportBuilder.makePackage(
                AIExportBuilder.Input(
                    accounts: accounts,
                    categories: categories,
                    transactions: allTxns,
                    claims: claims,
                    range: interval,
                    redacted: redacted
                )
            )
            fileURL = url
            errorMessage = nil
            Haptics.success()
        } catch {
            errorMessage = "生成失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }
}
