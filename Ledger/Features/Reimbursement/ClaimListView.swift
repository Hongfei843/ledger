import SwiftUI
import SwiftData

struct ClaimListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Claim.createdAt, order: .reverse) private var allClaims: [Claim]
    @Query(sort: \Txn.occurredAt, order: .reverse) private var allTxns: [Txn]
    @Query private var books: [Book]
    @AppStorage(BookScope.key) private var bookScopeRaw: String = ""

    @State private var showNew = false
    @State private var duplicateHint = false

    private var liveClaims: [Claim] {
        allClaims.filter { $0.deletedAt == nil && BookScope.matches($0.bookId, raw: bookScopeRaw) }
    }
    private var liveTxns: [Txn] {
        allTxns.filter { $0.deletedAt == nil && BookScope.matches($0.bookId, raw: bookScopeRaw) }
    }

    private var openClaims: [Claim] {
        liveClaims.filter { $0.status == .draft || $0.status == .submitted }
    }

    private var closedClaims: [Claim] {
        liveClaims.filter { $0.status == .reimbursed || $0.status == .closed }
    }

    private var monthPendingMinor: Int64 {
        StatsEngine.summary(
            range: AppCalendar.monthInterval(containing: Date()),
            caliber: .personal,
            txns: liveTxns,
            claims: liveClaims
        ).pendingMinor
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground)
            .listSectionSpacing(16)
            .ledgerTabBarClearance()
            .navigationTitle("报销")
            .navigationBarTitleDisplayMode(.inline)
            .alert("本月已有报销单", isPresented: $duplicateHint) {
                Button("好", role: .cancel) {}
            } message: {
                Text("草稿单已存在，垫付条目都记在同一单里，无需重复新建。")
            }
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
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Label("本月待报销", systemImage: "doc.text")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(openClaims.count) 单进行中")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            .foregroundStyle(.white.opacity(0.80))

            Text(Money.format(monthPendingMinor))
                .font(Theme.Fonts.amountXL)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)

            HStack {
                Label("垫付清晰，到账可查", systemImage: "checkmark.seal")
                Spacer()
                Text("已完成 \(closedClaims.count) 单")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 150, height: 150)
                .offset(x: 54, y: -64)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func claimRow(_ claim: Claim) -> some View {
        let items = liveTxns.filter { $0.claimId == claim.id && $0.type == .expense && $0.isReimbursable }
        let total = items.reduce(Int64(0)) { $0 + $1.amountMinor }
        return HStack(spacing: Theme.Spacing.m) {
            LedgerIconBadge(systemImage: claimIcon(claim.status), tint: badgeColor(claim.status), size: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(claim.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(claim.status.displayName)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(badgeColor(claim.status).opacity(0.12), in: Capsule())
                        .foregroundStyle(badgeColor(claim.status))
                }
                HStack {
                    Text("\(items.count) 笔 · \(claim.periodMonth)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.format(total))
                        .font(Theme.Fonts.amountM)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func claimIcon(_ status: ClaimStatus) -> String {
        switch status {
        case .draft: "doc.badge.plus"
        case .submitted: "paperplane"
        case .reimbursed: "checkmark.seal"
        case .closed: "archivebox"
        }
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
        guard let bookId = BookScope.currentId
            ?? books.first(where: { $0.deletedAt == nil && $0.isDefault })?.id
            ?? books.first(where: { $0.deletedAt == nil })?.id else { return }
        let monthKey = AppCalendar.monthKey(Date())
        // 记账页「可报销」已经自动建过当月草稿；这里再建一张会把垫付拆散到两张单。
        if liveClaims.contains(where: { $0.status == .draft && $0.periodMonth == monthKey }) {
            duplicateHint = true
            return
        }
        let claim = Claim(bookId: bookId, title: "\(monthKey) 报销", periodMonth: monthKey)
        context.insert(claim)
        PersistenceGuard.save(context, "报销单")
        Haptics.success()
    }
}
