import SwiftUI
import SwiftData

/// 流水详情：金额、分类、账户、备注，并列出同类别的其他记录。
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
        siblings
            .filter { $0.type == .expense }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
            }

            Section("明细") {
                detailRow(title: "类型", value: txn.type.displayName)
                detailRow(title: "分类", value: category?.name ?? "未分类")
                detailRow(title: "账户", value: account?.name ?? "—")
                if let counter = counterAccount {
                    detailRow(title: "对方账户", value: counter.name)
                }
                detailRow(title: "日期", value: DateFormatter.ledgerDateTime.string(from: txn.occurredAt))
                if let note = txn.note, !note.isEmpty {
                    detailRow(title: "备注", value: note)
                }
                if let payee = txn.payee, !payee.isEmpty {
                    detailRow(title: "商家", value: payee)
                }
                detailRow(title: "来源", value: sourceText)
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
                    Text("展示该分类下最近的记录，方便对比金额是否异常。")
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("删除这条记录")
                        .frame(maxWidth: .infinity)
                }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.m) {
                CategoryIconView(category: category, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category?.name ?? "未分类")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(signPrefix + Money.format(txn.amountMinor))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(txn.type == .income ? Theme.income : .primary)
                }
                Spacer()
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private var signPrefix: String {
        txn.type == .income ? "+" : (txn.type == .expense ? "-" : "")
    }

    private var sourceText: String {
        switch txn.source {
        case .manual: return "手动记账"
        case .imported: return "账单导入"
        case .recurring: return "周期记账"
        case .ocr: return "截图识别"
        case .sync: return "同步"
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
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
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    static let ledgerShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
