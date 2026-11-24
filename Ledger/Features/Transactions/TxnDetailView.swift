import SwiftUI
import SwiftData

/// 流水详情：紧凑排版，一屏看到金额、账户、日期、备注，并列出同类别对比。
struct TxnDetailView: View {
    let txn: Txn

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var categories: [Category]
    @Query private var accounts: [Account]

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    private var category: Category? {
        categories.first { $0.id == txn.categoryId }
    }

    private var account: Account? {
        accounts.first { $0.id == txn.accountId }
    }

    private var counterAccount: Account? {
        accounts.first { $0.id == txn.counterAccountId }
    }

    private var siblings: [Txn] {
        guard let categoryId = txn.categoryId else { return [] }
        return allTxns
            .filter { $0.deletedAt == nil && $0.categoryId == categoryId && $0.id != txn.id }
            .prefix(10)
            .map { $0 }
    }

    private var siblingTotal: Int64 {
        siblings.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    var body: some View {
        List {
            Section {
                header
            }

            if let note = txn.note, !note.isEmpty {
                Section("备注") {
                    Text(note)
                }
            }

            if let payee = txn.payee, !payee.isEmpty {
                Section("商家") {
                    Text(payee)
                }
            }

            if !siblings.isEmpty {
                Section {
                    ForEach(siblings, id: \.id) { item in
                        NavigationLink {
                            TxnDetailView(txn: item)
                        } label: {
                            siblingRow(item)
                        }
                    }
                } header: {
                    HStack {
                        Text("同类别的其他记录")
                        Spacer()
                        Text("共 \(Money.format(siblingTotal))")
                    }
                } footer: {
                    Text("展示该分类下最近的记录，方便对比这笔是否异常。")
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("删除这条记录")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text(sourceText)
            }
        }
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            EntrySheet(editingTxn: txn)
                .presentationDetents([.large])
        }
        .confirmationDialog("确定删除这条记录？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteTxn() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 头部：一行看完

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                CategoryIconView(category: category, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(category?.name ?? "未分类")
                        .font(.subheadline.weight(.medium))
                    Text(accountLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(signPrefix + Money.format(abs(txn.amountMinor)))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(txn.type == .income ? Theme.income : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    /// 「储蓄卡 · 11月23日 21:37」，转账时补上对方账户
    private var accountLine: String {
        var parts: [String] = []
        parts.append(account?.name ?? "—")
        if let counterAccount {
            parts.append("→ \(counterAccount.name)")
        }
        parts.append(DateFormatter.ledgerDateTime.string(from: txn.occurredAt))
        return parts.joined(separator: " · ")
    }

    private var signPrefix: String {
        switch txn.type {
        case .income: return "+"
        case .expense: return "-"
        case .adjustment: return txn.amountMinor >= 0 ? "+" : "-"
        default: return ""
        }
    }

    private var sourceText: String {
        switch txn.source {
        case .manual: return "来源：手动记账"
        case .imported: return "来源：账单导入"
        case .recurring: return "来源：周期记账"
        case .ocr: return "来源：截图识别"
        case .sync: return "来源：同步"
        }
    }

    private func siblingRow(_ item: Txn) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatter.ledgerShort.string(from: item.occurredAt))
                    .font(.subheadline)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(Money.format(item.amountMinor))
                .font(.subheadline)
                .monospacedDigit()
        }
    }

    private func deleteTxn() {
        txn.deletedAt = Date()
        txn.updatedAt = Date()
        try? context.save()

        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        BalanceService.refreshAll(accounts: accounts, transactions: all)
        try? context.save()

        Haptics.warning()
        dismiss()
    }
}

extension DateFormatter {
    static let ledgerDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static let ledgerShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
