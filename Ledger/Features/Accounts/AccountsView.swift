import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var txns: [Txn]
    @State private var showAdd = false
    @State private var editingAccount: Account?

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
                let items = activeAccounts.filter { !$0.type.isLiability }
                if items.isEmpty {
                    Text("暂无").foregroundStyle(.secondary)
                }
                ForEach(items, id: \.id) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        row(account)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            editingAccount = account
                        } label: {
                            Text("编辑")
                        }
                        .tint(Theme.accent)
                    }
                }
            }

            Section("负债") {
                let items = activeAccounts.filter { $0.type.isLiability }
                if items.isEmpty {
                    Text("暂无").foregroundStyle(.secondary)
                }
                ForEach(items, id: \.id) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        row(account)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            editingAccount = account
                        } label: {
                            Text("编辑")
                        }
                        .tint(Theme.accent)
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
            AccountEditView(account: nil)
        }
        .sheet(item: $editingAccount) { account in
            AccountEditView(account: account)
        }
    }

    private func row(_ account: Account) -> some View {
        let balance = BalanceService.balance(
            of: account,
            transactions: liveTxns,
            openingBalanceMinor: account.openingBalanceMinor
        )
        return HStack(spacing: Theme.Spacing.m) {
            BankMarkView(
                bankId: account.bankId,
                fallbackEmoji: account.iconEmoji,
                fallbackColorHex: account.colorHex,
                size: 38
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .lineLimit(1)
                Text(account.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(balance))
                .monospacedDigit()
                .foregroundStyle(balance < 0 ? Theme.danger : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
