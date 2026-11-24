import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var books: [Book]

    @State private var showPicker = false
    @State private var records: [CookieRecord] = []
    @State private var fileName = ""
    @State private var errorMessage: String?
    @State private var summary: ImportSummary?
    @State private var defaultAccountId: UUID?
    @State private var isWorking = false

    private var selectableAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
    }

    private var previewRecords: [CookieRecord] {
        Array(records.prefix(8))
    }

    private var categoryNames: [String] {
        Array(Set(records.map { $0.primaryCategory })).sorted()
    }

    var body: some View {
        Form {
            Section {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text(fileName.isEmpty ? "选择 CSV 文件" : fileName)
                        Spacer()
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            } footer: {
                Text("支持 Cookie 记账导出的 CSV（含表头「时间,收支,一级分类…」）。按原始记录 ID 去重，重复导入不会产生重复账。")
            }

            if !records.isEmpty {
                Section("识别结果") {
                    LabeledContent("记录条数", value: "\(records.count)")
                    LabeledContent("支出", value: "\(records.filter { !$0.isIncome }.count) 笔")
                    LabeledContent("收入", value: "\(records.filter { $0.isIncome }.count) 笔")
                    LabeledContent("时间范围", value: "\(dateText(records.map { $0.occurredAt }.min())) ~ \(dateText(records.map { $0.occurredAt }.max()))")
                }

                Section("未指定卡包的记录归入") {
                    Picker("默认账户", selection: $defaultAccountId) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(selectableAccounts, id: \.id) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }

                Section("识别到的分类（会自动创建）") {
                    Text(categoryNames.joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("预览") {
                    ForEach(Array(previewRecords.enumerated()), id: \.offset) { _, record in
                        HStack {
                            Text(record.emoji ?? "📦")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.note ?? record.primaryCategory)
                                    .font(.subheadline)
                                Text("\(dateText(record.occurredAt)) · \(record.primaryCategory)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(record.amountMinor))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(record.isIncome ? Theme.income : .primary)
                        }
                    }
                }

                Section {
                    Button {
                        runImport()
                    } label: {
                        Text(isWorking ? "导入中…" : "导入 \(records.count) 条记录")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(defaultAccountId == nil || isWorking)
                }
            }
        }
        .navigationTitle("导入账单")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handlePick(result)
        }
        .alert("导入完成", isPresented: Binding(
            get: { summary != nil },
            set: { if !$0 { summary = nil } }
        )) {
            Button("好") {
                records = []
                fileName = ""
            }
        } message: {
            Text(summary?.description ?? "")
        }
        .onAppear {
            if defaultAccountId == nil {
                defaultAccountId = selectableAccounts.first?.id
            }
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return DateFormatter.ledgerShort.string(from: date)
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        errorMessage = nil
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            guard let text = decode(data) else {
                errorMessage = "无法识别文件编码"
                return
            }
            let parsed = try CookieCSVImporter.parse(text: text)
            fileName = url.lastPathComponent
            records = parsed
            if parsed.isEmpty {
                errorMessage = "没有解析到任何记录"
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        let gb18030 = String.Encoding(rawValue: 0x80000632)
        return String(data: data, encoding: gb18030)
    }

    private func runImport() {
        guard let accountId = defaultAccountId, let bookId = books.first?.id else { return }
        isWorking = true
        let result = ImportService.importCookie(
            records: records,
            defaultAccountId: accountId,
            bookId: bookId,
            context: context
        )
        summary = result
        isWorking = false
    }
}
