import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// 账单比对：把支付宝/微信导出的 CSV 与本地流水逐条核对。
struct BillCompareView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
    @Query private var accounts: [Account]
    @Query private var books: [Book]

    @State private var showPicker = false
    @State private var rows: [BillRow] = []
    @State private var result: BillCompareResult?
    @State private var sourceName = ""
    @State private var errorMessage: String?
    @State private var accountId: UUID?
    @State private var toast: String?

    private var selectableAccounts: [Account] {
        accounts.filter { $0.deletedAt == nil && !$0.isArchived && !$0.isSystem }
    }

    var body: some View {
        Form {
            Section {
                Button {
                    showPicker = true
                } label: {
                    Label(sourceName.isEmpty ? "选择账单 CSV" : sourceName, systemImage: "doc.badge.plus")
                }
                Button {
                    parseClipboard()
                } label: {
                    Label("从剪贴板读取", systemImage: "doc.on.clipboard")
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(Theme.danger)
                }
            } footer: {
                Text("支持支付宝、微信导出的账单 CSV。比对不会改动数据，只告诉你「谁多谁少」。")
            }

            if let result {
                Section("比对结果") {
                    row("账单条数", "\(result.totalRows)")
                    row("已对上", "\(result.matchedCount)")
                    row("漏记（账单有、App 没有）", "\(result.missing.count)")
                    row("多记（App 有、账单没有）", "\(result.extra.count)")
                }

                if !result.missing.isEmpty {
                    Section {
                        Picker("补录到账户", selection: $accountId) {
                            Text("请选择").tag(UUID?.none)
                            ForEach(selectableAccounts, id: \.id) { account in
                                Text(account.displayName).tag(UUID?.some(account.id))
                            }
                        }
                        Button {
                            fillMissing(result.missing)
                        } label: {
                            Text("全部补录 \(result.missing.count) 条")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(accountId == nil)
                    } header: {
                        Text("漏记明细")
                    } footer: {
                        Text("补录后分类为「其他」，可以在明细里再改。")
                    }

                    ForEach(result.missing.prefix(30)) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.counterparty ?? item.subject ?? "未知")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(item.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(item.amountMinor))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(item.isIncome ? Theme.income : .primary)
                        }
                    }
                }

                if !result.extra.isEmpty {
                    Section {
                        ForEach(result.extra.prefix(20), id: \.id) { txn in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(txn.note ?? txn.type.displayName)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(txn.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.format(abs(txn.amountMinor)))
                                    .font(.subheadline)
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        Text("多记明细")
                    } footer: {
                        Text("账单里找不到对应记录，可能是手动记的、或金额/日期有偏差。")
                    }
                }

                if result.missing.isEmpty && result.extra.isEmpty {
                    Section {
                        Label("账目完全对上", systemImage: "checkmark.seal")
                            .foregroundStyle(Theme.income)
                    }
                }
            }
        }
        .navigationTitle("账单比对")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            DocumentPicker(allowedTypes: [.item]) { url in
                showPicker = false
                handlePick(url)
            } onCancel: {
                showPicker = false
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if accountId == nil { accountId = selectableAccounts.first?.id }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    // MARK: - 解析

    private func handlePick(_ url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let text = decode(data) else {
                errorMessage = "无法识别文件编码"
                return
            }
            sourceName = url.lastPathComponent
            try analyze(text: text)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            errorMessage = "剪贴板里没有文本"
            return
        }
        sourceName = "剪贴板内容"
        do {
            try analyze(text: text)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func analyze(text: String) throws {
        errorMessage = nil
        let parsed = try BillCSVParser.parse(text: text)
        rows = parsed.rows
        result = BillMatcher.compare(rows: parsed.rows, transactions: txns)
        Haptics.success()
    }

    private func decode(_ data: Data) -> String? {
        ImportTextDecoder.decode(data)
    }

    // MARK: - 补录

    private func fillMissing(_ items: [BillRow]) {
        guard let accountId, let bookId = books.first?.id else { return }
        let inserted = ImportService.importBillRows(
            items,
            accountId: accountId,
            bookId: bookId,
            categoryId: nil,
            context: context
        )
        withAnimation {
            toast = "已补录 \(inserted) 条"
        }
        Haptics.success()

        // 补录后重新比对
        let refreshed = (try? context.fetch(FetchDescriptor<Txn>()))?.filter { $0.deletedAt == nil } ?? txns
        result = BillMatcher.compare(rows: rows, transactions: refreshed)

        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }
}
