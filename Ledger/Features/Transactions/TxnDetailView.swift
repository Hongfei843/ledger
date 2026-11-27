import SwiftUI
import SwiftData

/// 流水详情：金额、账户、日期、备注，退款关系与同类别对比。
struct TxnDetailView: View {
    let txn: Txn

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var categories: [Category]
    @Query private var accounts: [Account]
    @Query private var statements: [Statement]
    @Query private var loans: [Loan]

    @State private var showEdit = false
    @State private var showRefund = false
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

    private var refunds: [Txn] {
        RefundService.refunds(of: txn, all: allTxns)
    }

    private var refundedMinor: Int64 {
        RefundService.refundedMinor(of: txn, all: allTxns)
    }

    private var remainingRefundableMinor: Int64 {
        RefundService.remainingRefundableMinor(of: txn, all: allTxns)
    }

    private var originalTxn: Txn? {
        guard let id = txn.refundOfTxnId else { return nil }
        return allTxns.first { $0.id == id && $0.deletedAt == nil }
    }

    private var siblings: [Txn] {
        guard let categoryId = txn.categoryId else { return [] }
        return allTxns
            .filter {
                $0.deletedAt == nil
                    && $0.categoryId == categoryId
                    && $0.id != txn.id
                    && !RefundService.isRefund($0)
            }
            .prefix(10)
            .map { $0 }
    }

    private var siblingTotal: Int64 {
        siblings.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var deletePrompt: String {
        refunds.isEmpty ? "确定删除这条记录？" : "删除这笔支出和 \(refunds.count) 笔关联退款？"
    }

    var body: some View {
        List {
            Section {
                header
            }

            if let originalTxn {
                refundSourceSection(originalTxn)
            }

            if txn.type == .expense && txn.source != .reimbursement && txn.loanId == nil {
                refundActionSection
            }

            if !refunds.isEmpty {
                refundListSection
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
                siblingsSection
            }

            if txn.canDeleteFromTransactionList {
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
            } else if let loanId = txn.loanId, let loan = loans.first(where: { $0.id == loanId }) {
                Section {
                    NavigationLink {
                        LoanDetailView(loan: loan)
                    } label: {
                        Label("前往贷款详情管理这笔还款", systemImage: "house")
                    }
                } footer: {
                    Text("贷款还款与还款计划联动，不能在通用流水页直接修改或删除。")
                }
            }
        }
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if txn.canEditInEntrySheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { showEdit = true }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            EntrySheet(editingTxn: txn)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showRefund) {
            RefundSheet(original: txn, alreadyRefundedMinor: refundedMinor)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(deletePrompt, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
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
                    HStack(spacing: 6) {
                        Text(category?.name ?? "未分类")
                            .font(.subheadline.weight(.medium))
                        if txn.isRefund {
                            Text("退款")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.income.opacity(0.14), in: Capsule())
                                .foregroundStyle(Theme.income)
                        }
                    }
                    Text(accountLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(signPrefix + Money.format(abs(txn.amountMinor)))
                    .font(Theme.Fonts.amountL)
                    .monospacedDigit()
                    .foregroundStyle(txn.type == .income ? Theme.income : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            if refundedMinor > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                    Text("已退款 \(Money.format(refundedMinor))")
                    if remainingRefundableMinor > 0 {
                        Text("· 剩余可退 \(Money.format(remainingRefundableMinor))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.income)
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
        case .reimbursement: return "来源：报销到账时自动生成的差额，不属于新的现金支出"
        }
    }

    // MARK: - 退款

    private func refundSourceSection(_ original: Txn) -> some View {
        Section {
            NavigationLink {
                TxnDetailView(txn: original)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("原支出")
                            .font(.subheadline)
                        Text(DateFormatter.ledgerDateTime.string(from: original.occurredAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Money.format(original.amountMinor))
                        .font(Theme.Fonts.amountM)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("关联支出")
        } footer: {
            Text("这笔退款已从原支出里冲减，不会重复计入收入。")
        }
    }

    private var refundActionSection: some View {
        Section {
            if refundedMinor > 0 {
                HStack {
                    Text("已退款")
                    Spacer()
                    Text(Money.format(refundedMinor))
                        .monospacedDigit()
                        .foregroundStyle(Theme.income)
                }
                HStack {
                    Text("可退剩余")
                    Spacer()
                    Text(Money.format(remainingRefundableMinor))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if remainingRefundableMinor > 0 {
                Button {
                    showRefund = true
                } label: {
                    Label("记一笔退款", systemImage: "arrow.uturn.backward.circle")
                }
            }
        } header: {
            Text("退款")
        } footer: {
            if refundedMinor > 0 {
                Text("退款流水在下方「退款记录」里，可以点进去查看或删除。")
            } else {
                Text("退款会冲减这笔支出：统计里不算收入，原分类金额直接减少。")
            }
        }
    }

    private var refundListSection: some View {
        Section {
            ForEach(refunds, id: \.id) { item in
                NavigationLink {
                    TxnDetailView(txn: item)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(refundTitle(item))
                                .font(.subheadline)
                            Text(DateFormatter.ledgerDateTime.string(from: item.occurredAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+" + Money.format(item.amountMinor))
                            .font(Theme.Fonts.amountM)
                            .monospacedDigit()
                            .foregroundStyle(Theme.income)
                    }
                }
            }
        } header: {
            HStack {
                Text("退款记录")
                Spacer()
                Text("共 \(refunds.count) 笔")
            }
        }
    }

    private func refundTitle(_ item: Txn) -> String {
        if let note = item.note, !note.isEmpty { return note }
        return "退款"
    }

    // MARK: - 同类对比

    private var siblingsSection: some View {
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
                .font(Theme.Fonts.amountM)
                .monospacedDigit()
        }
    }

    private func deleteTxn() {
        var victims: [Txn] = [txn]
        if txn.type == .expense {
            victims.append(contentsOf: refunds)
        }
        for item in victims {
            item.deletedAt = Date()
            item.updatedAt = Date()
        }
        if txn.type == .transfer, let creditAccountId = txn.counterAccountId {
            StatementSettlementService.rebuild(
                accountId: creditAccountId,
                transactions: allTxns,
                statements: statements
            )
        }
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
