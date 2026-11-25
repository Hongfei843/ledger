import Foundation

/// 生成「AI 分析包」：一个 ZIP，内含摘要、结构化数据、明细与完整备份。
/// 面向两种用途：① 喂给 AI 分析 ② 灾备恢复。
enum AIExportBuilder {
    struct Input {
        let accounts: [Account]
        let categories: [Category]
        let transactions: [Txn]
        let claims: [Claim]
        let range: DateInterval
        let redacted: Bool
    }

    private static let csvDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func makePackage(_ input: Input) throws -> URL {
        let liveTxns = input.transactions.filter { $0.deletedAt == nil }
        let scoped = liveTxns.filter { input.range.contains($0.occurredAt) }
        let monthKey = AppCalendar.monthKey(input.range.start)

        let summary = StatsEngine.summary(
            range: input.range,
            caliber: .personal,
            txns: liveTxns,
            claims: input.claims
        )
        let slices = StatsEngine.byCategory(
            range: input.range,
            caliber: .personal,
            txns: liveTxns,
            claims: input.claims,
            categories: input.categories
        )
        let months = StatsEngine.byMonth(months: 6, endingAt: input.range.end, txns: liveTxns)

        let displayAccounts = accountNames(input: input)

        let entries: [ZipEntry] = [
            ZipEntry(name: "00-README.md", data: readmeData()),
            ZipEntry(name: "01-summary.md", data: summaryMarkdown(input: input, summary: summary, slices: slices, months: months, monthKey: monthKey, scoped: scoped).data(using: .utf8) ?? Data()),
            ZipEntry(name: "02-summary.json", data: try summaryJSON(input: input, summary: summary, slices: slices, months: months, monthKey: monthKey)),
            ZipEntry(name: "03-transactions.csv", data: transactionsCSV(scoped, input: input, names: displayAccounts).data(using: .utf8) ?? Data()),
            ZipEntry(name: "04-monthly.csv", data: monthsCSV(months).data(using: .utf8) ?? Data()),
            ZipEntry(name: "05-category.csv", data: categoryCSV(slices).data(using: .utf8) ?? Data()),
            ZipEntry(name: "06-accounts.csv", data: accountsCSV(input: input, liveTxns: liveTxns, names: displayAccounts).data(using: .utf8) ?? Data()),
            ZipEntry(name: "07-backup.json", data: try backupJSON(input: input))
        ]

        let data = ZipWriter.archive(entries)
        let fileName = "ai-pack-\(monthKey).zip"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 名称映射（脱敏用）

    private struct AccountNames {
        var map: [UUID: String]
        func name(_ id: UUID?) -> String {
            guard let id else { return "—" }
            return map[id] ?? "—"
        }
    }

    private static func accountNames(input: Input) -> AccountNames {
        var map: [UUID: String] = [:]
        for (index, account) in input.accounts.enumerated() {
            map[account.id] = input.redacted ? "账户\(index + 1)" : account.name
        }
        return AccountNames(map: map)
    }

    private static func note(_ txn: Txn, redacted: Bool) -> String {
        guard !redacted else { return txn.note?.isEmpty == false ? "***" : "" }
        return txn.note ?? ""
    }

    private static func categoryName(_ id: UUID?, categories: [Category]) -> String {
        guard let id else { return "未分类" }
        return categories.first { $0.id == id }?.name ?? "未分类"
    }

    // MARK: - 各文件内容

    private static func readmeData() -> Data {
        let text = """
        # 这个压缩包是什么

        由「记账」App 导出的 AI 分析包，包含最近一段时间的收支数据。
        默认已脱敏：商户名与备注被替换为 ***，账户名替换为「账户1/2」。

        ## 文件说明

        | 文件 | 内容 |
        |---|---|
        | 01-summary.md | 人类与 AI 都好读的摘要（收支、分类、趋势、数据质量） |
        | 02-summary.json | 同内容的机器可读版本 |
        | 03-transactions.csv | 明细流水 |
        | 04-monthly.csv | 月度汇总 |
        | 05-category.csv | 分类汇总 |
        | 06-accounts.csv | 账户与负债快照 |
        | 07-backup.json | 完整备份，可被 App 恢复 |

        ## 可以直接问 AI 的问题

        1. 分析我最近 6 个月的消费结构变化，指出增长最快的 3 个类别及可能原因。
        2. 找出可以削减的非必要支出，按可节省金额排序。
        3. 我的固定支出（房租/订阅/还款）占比是否过高？如果收入下降 20%，应该先砍哪些？
        4. 结合我的负债与还款计划，评估提前还贷是否划算。
        """
        return Data(text.utf8)
    }

    private static func summaryMarkdown(
        input: Input,
        summary: StatsSummary,
        slices: [CategorySlice],
        months: [MonthBucket],
        monthKey: String,
        scoped: [Txn]
    ) -> String {
        var lines: [String] = []
        lines.append("# 记账数据分析包 \(monthKey)")
        lines.append("")
        lines.append("- 时间范围：\(csvDateFormatter.string(from: input.range.start)) ~ \(csvDateFormatter.string(from: input.range.end))")
        lines.append("- 记录条数：\(scoped.count)")
        lines.append("- 脱敏：\(input.redacted ? "是" : "否")")
        lines.append("")

        lines.append("## 收支总览")
        lines.append("")
        lines.append("| 项目 | 金额 |")
        lines.append("|---|---:|")
        lines.append("| 收入 | \(Money.formatPlain(summary.incomeMinor)) |")
        lines.append("| 支出 | \(Money.formatPlain(summary.expenseMinor)) |")
        lines.append("| 结余 | \(Money.formatPlain(summary.balanceMinor)) |")
        lines.append("| 储蓄率 | \(String(format: "%.1f%%", summary.savingRate * 100)) |")
        if summary.pendingMinor > 0 {
            lines.append("| 待报销（已从支出中剔除） | \(Money.formatPlain(summary.pendingMinor)) |")
        }
        lines.append("")

        if !slices.isEmpty {
            lines.append("## 分类支出 Top 10")
            lines.append("")
            lines.append("| 分类 | 金额 | 占比 | 笔数 |")
            lines.append("|---|---:|---:|---:|")
            let total = max(1, slices.reduce(Int64(0)) { $0 + $1.amountMinor })
            for slice in slices.prefix(10) {
                let ratio = Double(slice.amountMinor) / Double(total) * 100
                lines.append("| \(slice.name) | \(Money.formatPlain(slice.amountMinor)) | \(String(format: "%.1f%%", ratio)) | \(slice.count) |")
            }
            lines.append("")
        }

        if !months.isEmpty {
            lines.append("## 近 6 个月趋势")
            lines.append("")
            lines.append("| 月份 | 收入 | 支出 |")
            lines.append("|---|---:|---:|")
            for bucket in months {
                lines.append("| \(bucket.id) | \(Money.formatPlain(bucket.incomeMinor)) | \(Money.formatPlain(bucket.expenseMinor)) |")
            }
            lines.append("")
        }

        // 数据质量：让 AI 知道数据坑在哪
        let uncategorized = scoped.filter { $0.categoryId == nil }.count
        let unknownAccounts = scoped.filter { txn in
            !input.accounts.contains { $0.id == txn.accountId }
        }.count
        let missingNote = scoped.filter { ($0.note ?? "").isEmpty }.count
        lines.append("## 数据质量提示")
        lines.append("")
        lines.append("- 未分类记录：\(uncategorized) 条")
        lines.append("- 账户缺失记录：\(unknownAccounts) 条")
        lines.append("- 无备注记录：\(missingNote) 条")
        if input.redacted {
            lines.append("- 本包已脱敏：商户名、备注、账户名均被替换")
        }
        lines.append("")
        lines.append("> 若「未分类」或「账户缺失」占比很高，请提醒用户先完善分类再分析，避免结论偏差。")
        return lines.joined(separator: "\n")
    }

    private static func summaryJSON(
        input: Input,
        summary: StatsSummary,
        slices: [CategorySlice],
        months: [MonthBucket],
        monthKey: String
    ) throws -> Data {
        let payload: [String: Any] = [
            "month": monthKey,
            "rangeStart": isoFormatter.string(from: input.range.start),
            "rangeEnd": isoFormatter.string(from: input.range.end),
            "currency": "CNY",
            "income": Money.formatPlain(summary.incomeMinor),
            "expense": Money.formatPlain(summary.expenseMinor),
            "balance": Money.formatPlain(summary.balanceMinor),
            "savingRate": summary.savingRate,
            "pendingReimbursement": Money.formatPlain(summary.pendingMinor),
            "categories": slices.map { slice in
                [
                    "name": slice.name,
                    "amount": Money.formatPlain(slice.amountMinor),
                    "count": slice.count
                ] as [String: Any]
            },
            "monthly": months.map { bucket in
                [
                    "month": bucket.id,
                    "income": Money.formatPlain(bucket.incomeMinor),
                    "expense": Money.formatPlain(bucket.expenseMinor)
                ] as [String: Any]
            }
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func transactionsCSV(_ txns: [Txn], input: Input, names: AccountNames) -> String {
        var lines = ["日期,时间,类型,金额,币种,账户,分类,备注,可报销,来源,记录ID,退款原记录ID"]
        for txn in txns.sorted(by: { $0.occurredAt > $1.occurredAt }) {
            let date = csvDateFormatter.string(from: txn.occurredAt)
            let parts = date.split(separator: " ")
            let day = parts.first.map(String.init) ?? date
            let time = parts.count > 1 ? String(parts[1]) : ""
            let row = [
                day,
                time,
                txn.type.displayName,
                Money.formatPlain(txn.amountMinor),
                "CNY",
                names.name(txn.accountId),
                categoryName(txn.categoryId, categories: input.categories),
                note(txn, redacted: input.redacted),
                txn.isReimbursable ? "是" : "否",
                txn.source.rawValue,
                txn.id.uuidString,
                txn.refundOfTxnId?.uuidString ?? ""
            ].map(csvField)
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func monthsCSV(_ months: [MonthBucket]) -> String {
        var lines = ["月份,收入,支出"]
        for bucket in months {
            lines.append([bucket.id, Money.formatPlain(bucket.incomeMinor), Money.formatPlain(bucket.expenseMinor)].map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func categoryCSV(_ slices: [CategorySlice]) -> String {
        var lines = ["分类,金额,笔数,占比"]
        let total = max(1, slices.reduce(Int64(0)) { $0 + $1.amountMinor })
        for slice in slices {
            let ratio = String(format: "%.1f%%", Double(slice.amountMinor) / Double(total) * 100)
            lines.append([slice.name, Money.formatPlain(slice.amountMinor), "\(slice.count)", ratio].map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func accountsCSV(input: Input, liveTxns: [Txn], names: AccountNames) -> String {
        var lines = ["账户,类型,余额,计入净资产"]
        for account in input.accounts where account.deletedAt == nil {
            let balance = BalanceService.balance(
                of: account,
                transactions: liveTxns,
                openingBalanceMinor: account.openingBalanceMinor
            )
            lines.append([
                names.name(account.id),
                account.type.displayName,
                Money.formatPlain(balance),
                account.includeInNetWorth ? "是" : "否"
            ].map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func backupJSON(input: Input) throws -> Data {
        let accounts = input.accounts.map { account -> [String: Any] in
            [
                "id": account.id.uuidString,
                "name": account.name,
                "type": account.type.rawValue,
                "openingBalanceMinor": account.openingBalanceMinor,
                "cachedBalanceMinor": account.cachedBalanceMinor,
                "includeInNetWorth": account.includeInNetWorth,
                "isArchived": account.isArchived
            ]
        }
        let categories = input.categories.map { category -> [String: Any] in
            [
                "id": category.id.uuidString,
                "name": category.name,
                "kind": category.kind.rawValue,
                "iconEmoji": category.iconEmoji
            ]
        }
        let transactions = input.transactions.filter { $0.deletedAt == nil }.map { txn -> [String: Any] in
            [
                "id": txn.id.uuidString,
                "type": txn.type.rawValue,
                "amountMinor": txn.amountMinor,
                "accountId": txn.accountId.uuidString,
                "categoryId": txn.categoryId?.uuidString ?? "",
                "occurredAt": isoFormatter.string(from: txn.occurredAt),
                "note": txn.note ?? "",
                "isReimbursable": txn.isReimbursable,
                "refundOfTxnId": txn.refundOfTxnId?.uuidString ?? "",
                "source": txn.source.rawValue
            ]
        }
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "exportedAt": isoFormatter.string(from: Date()),
            "accounts": accounts,
            "categories": categories,
            "transactions": transactions
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}
