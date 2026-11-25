import SwiftUI
import SwiftData

struct ClaimListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Claim.createdAt, order: .reverse) private var allClaims: [Claim]
    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var books: [Book]

    @State private var showNew = false

    private var liveClaims: [Claim] { allClaims.filter { $0.deletedAt == nil } }
    private var liveTxns: [Txn] { allTxns.filter { $0.deletedAt == nil } }

    private var openClaims: [Claim] {
        liveClaims.filter { $0.status == .draft || $0.status == .submitted }
    }

    private var closedClaims: [Claim] {
        liveClaims.filter { $0.status == .reimbursed || $0.status == .closed }
    }

    private var monthPendingMinor: Int64 {
        let interval = AppCalendar.monthInterval(containing: Date())
        return liveTxns
            .filter { $0.type == .expense && $0.isReimbursable && interval.contains($0.occurredAt) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCard
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("进行中") {
                    if openClaims.isEmpty {
                        Text("暂无").foregroundStyle(.secondary)
                    }
                    ForEach(openClaims, id: \.id) { claim in
                        NavigationLink {
                            ClaimDetailView(claim: claim)
                        } label: {
                            claimRow(claim)
                        }
                    }
                }

                Section("已完成") {
                    if closedClaims.isEmpty {
                        Text("暂无").foregroundStyle(.secondary)
                    }
                    ForEach(closedClaims, id: \.id) { claim in
                        NavigationLink {
                            ClaimDetailView(claim: claim)
                        } label: {
                            claimRow(claim)
                        }
                    }
                }
            }
            .navigationTitle("报销")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ClaimReportView()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { createClaim() } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("本月垫付")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Money.format(monthPendingMinor))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func claimRow(_ claim: Claim) -> some View {
        let items = liveTxns.filter { $0.claimId == claim.id && $0.type == .expense }
        let total = items.reduce(Int64(0)) { $0 + $1.amountMinor }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(claim.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(claim.status.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor(claim.status).opacity(0.14), in: Capsule())
                    .foregroundStyle(badgeColor(claim.status))
            }
            HStack {
                Text("\(items.count) 笔 · \(claim.periodMonth)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Money.format(total))
                    .font(.subheadline)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private func badgeColor(_ status: ClaimStatus) -> Color {
        switch status {
        case .draft: return .secondary
        case .submitted: return Theme.warning
        case .reimbursed: return Theme.income
        case .closed: return .secondary
        }
    }

    private func createClaim() {
        let bookId = books.first?.id ?? UUID()
        let monthKey = AppCalendar.monthKey(Date())
        let claim = Claim(bookId: bookId, title: "\(monthKey) 报销", periodMonth: monthKey)
        context.insert(claim)
        try? context.save()
        Haptics.success()
    }
}
