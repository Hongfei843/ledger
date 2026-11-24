import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var txns: [Txn]
    @State private var showAdd = false

    private var activeAccounts: [Account] {
        accounts
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var liveTxns: [Txn] {
        txns.filter { $0.deletedAt == nil }
    }

    var body: some View {
        List {
            Section("资产") {
                ForEach(activeAccounts.filter { !$0.type.isLiability }, id: \.id) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        row(account)
                    }
                }
            }
            Section("负债") {
                let liabilities = activeAccounts.filter { $0.type.isLiability }
                if liabilities.isEmpty {
                    Text("暂无")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(liabilities, id: \.id) { account in
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
                            row(account)
                        }
                    }
                }
            }
        }
        .navigationTitle("账户")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddAccountSheet()
        }
    }

    private func row(_ account: Account) -> some View {
        let balance = BalanceService.balance(
            of: account,
            transactions: liveTxns,
            openingBalanceMinor: account.openingBalanceMinor
        )
        return HStack(spacing: Theme.Spacing.m) {
            Text(account.iconEmoji)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(Color(hexString: account.colorHex).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(balance))
                .monospacedDigit()
                .foregroundStyle(balance < 0 ? Theme.danger : .primary)
        }
    }
}

struct AddAccountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]

    @State private var name = ""
    @State private var type: AccountType = .debit
    @State private var balanceText = "0"

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如 招行储蓄卡", text: $name)
                }
                Section("类型") {
                    Picker("类型", selection: $type) {
                        ForEach(AccountType.allCases.filter { $0 != .loan }, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }
                Section("期初余额") {
                    TextField("0.00", text: $balanceText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("新建账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let bookId = books.first?.id ?? UUID()
        let opening = Money.parse(balanceText) ?? 0
        let account = Account(
            bookId: bookId,
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            openingBalanceMinor: opening
        )
        context.insert(account)
        try? context.save()
        dismiss()
    }
}
