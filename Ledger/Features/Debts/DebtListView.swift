import SwiftUI
import SwiftData

struct DebtListView: View {
    @Environment(\.modelContext) private var context
    @Query private var debts: [Debt]
    @Query private var books: [Book]

    @State private var showAdd = false
    @State private var editing: Debt?

    private var live: [Debt] {
        debts.filter { $0.deletedAt == nil }
    }

    private var openLend: [Debt] {
        live.filter { $0.direction == .lend && !$0.isSettled }.sorted { $0.occurredAt > $1.occurredAt }
    }

    private var openBorrow: [Debt] {
        live.filter { $0.direction == .borrow && !$0.isSettled }.sorted { $0.occurredAt > $1.occurredAt }
    }

    private var settled: [Debt] {
        live.filter { $0.isSettled }.sorted { ($0.settledAt ?? $0.occurredAt) > ($1.settledAt ?? $1.occurredAt) }
    }

    private var summary: (receivable: Int64, payable: Int64) {
        DebtService.summary(live)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("应收").font(.caption2).foregroundStyle(.secondary)
                        Text(Money.format(summary.receivable))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.income)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("应付").font(.caption2).foregroundStyle(.secondary)
                        Text(Money.format(summary.payable))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.warning)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            section(title: "别人欠我", items: openLend)
            section(title: "我欠别人", items: openBorrow)
            section(title: "已结清", items: settled)
        }
        .navigationTitle("借入借出")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            DebtEditView(debt: nil)
        }
        .sheet(item: $editing) { debt in
            DebtEditView(debt: debt)
        }
    }

    private func section(title: String, items: [Debt]) -> some View {
        Section(title) {
            if items.isEmpty {
                Text("暂无").foregroundStyle(.secondary)
            }
            ForEach(items, id: \.id) { debt in
                Button {
                    editing = debt
                } label: {
                    row(debt)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    if !debt.isSettled {
                        Button {
                            debt.isSettled = true
                            debt.settledAt = Date()
                            debt.updatedAt = Date()
                            try? context.save()
                            Haptics.success()
                        } label: {
                            Text("结清")
                        }
                        .tint(Theme.income)
                    }
                    Button(role: .destructive) {
                        debt.deletedAt = Date()
                        debt.updatedAt = Date()
                        try? context.save()
                    } label: {
                        Text("删除")
                    }
                }
            }
        }
    }

    private func row(_ debt: Debt) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(debt.direction == .lend ? "📤" : "📥")
                .font(.system(size: 18))
                .frame(width: 34, height: 34)
                .background(Color(.secondarySystemBackground), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(debt.counterparty)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(debt.direction.displayName)
                    Text(DateFormatter.ledgerShort.string(from: debt.occurredAt))
                    if let due = debt.dueDate {
                        Text(debt.isOverdue() ? "逾期" : "至 \(DateFormatter.ledgerShort.string(from: due))")
                            .foregroundStyle(debt.isOverdue() ? Theme.danger : .secondary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(Money.format(debt.amountMinor))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(debt.direction == .lend ? Theme.income : Theme.warning)
        }
    }
}

struct DebtEditView: View {
    let debt: Debt?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]

    @State private var direction: DebtDirection = .lend
    @State private var counterparty = ""
    @State private var amountText = ""
    @State private var occurredAt = Date()
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("方向", selection: $direction) {
                        Text("我借出").tag(DebtDirection.lend)
                        Text("我借入").tag(DebtDirection.borrow)
                    }
                    .pickerStyle(.segmented)
                }

                Section("对方与金额") {
                    TextField("对方，如 张三", text: $counterparty)
                    TextField("金额（元）", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("发生日期", selection: $occurredAt, displayedComponents: .date)
                }

                Section("还款日期") {
                    Toggle("设置还款日", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("应还日期", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("备注") {
                    TextField("可选", text: $note)
                }
            }
            .navigationTitle(debt == nil ? "记一笔借贷" : "编辑借贷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var canSave: Bool {
        !counterparty.trimmingCharacters(in: .whitespaces).isEmpty && (Money.parse(amountText) ?? 0) > 0
    }

    private func load() {
        guard let debt else { return }
        direction = debt.direction
        counterparty = debt.counterparty
        amountText = Money.rawText(debt.amountMinor)
        occurredAt = debt.occurredAt
        hasDueDate = debt.dueDate != nil
        dueDate = debt.dueDate ?? Date()
        note = debt.note ?? ""
    }

    private func save() {
        guard let amount = Money.parse(amountText), amount > 0 else { return }
        let name = counterparty.trimmingCharacters(in: .whitespaces)

        if let debt {
            debt.direction = direction
            debt.counterparty = name
            debt.amountMinor = amount
            debt.occurredAt = occurredAt
            debt.dueDate = hasDueDate ? dueDate : nil
            debt.note = note.isEmpty ? nil : note
            debt.updatedAt = Date()
        } else {
            let bookId = books.first?.id ?? UUID()
            let created = Debt(
                bookId: bookId,
                direction: direction,
                counterparty: name,
                amountMinor: amount,
                occurredAt: occurredAt,
                dueDate: hasDueDate ? dueDate : nil
            )
            created.note = note.isEmpty ? nil : note
            context.insert(created)
        }

        try? context.save()
        Haptics.success()
        dismiss()
    }
}
