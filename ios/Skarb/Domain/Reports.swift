import Foundation

/// How the overview's spending ring breaks the window down.
nonisolated enum Breakdown: String, Hashable, CaseIterable, Sendable {
    case category, account, tag

    var label: String {
        switch self {
        case .category: "Categories"
        case .account: "Accounts"
        case .tag: "Tags"
        }
    }
}

/// One wedge of the spending ring, whichever way the window is broken down. Colors stay stored
/// hex strings here; the view decides how they render in the current appearance.
nonisolated struct SpendingSlice: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    /// Nil is the neutral grey of "Uncategorized", "Untagged" and "Other".
    var colorHex: String?
    var amount: Decimal
    /// Where tapping this wedge goes, when there are transactions behind it.
    var filter: TransactionFilter?
    /// The longer form of the name, for a legend line too narrow to hold it.
    var hint: String?
}

nonisolated enum SpendingBreakdown {
    /// Six wedges plus an "Other" catch-all — more than that and the ring stops being readable.
    static let visibleSlices = 6

    static func slices(_ data: Dashboard, by breakdown: Breakdown) -> [SpendingSlice] {
        let all: [SpendingSlice]
        switch breakdown {
        case .category:
            all = data.spendingByCategory.map {
                SpendingSlice(
                    id: $0.categoryId?.uuidString ?? "uncategorized", name: $0.name,
                    colorHex: $0.color, amount: $0.amount,
                    filter: $0.categoryId.map { TransactionFilter(categoryId: $0) })
            }
        case .account:
            // Which account the window left from. The legend is narrow, so the account name
            // carries the line and the bank rides along underneath.
            all = data.spendingByAccount.map {
                SpendingSlice(
                    id: $0.accountId.uuidString, name: $0.name, colorHex: $0.color, amount: $0.amount,
                    filter: TransactionFilter(accountId: $0.accountId),
                    hint: $0.bank.isEmpty ? nil : $0.bank)
            }
        case .tag:
            // Tagged spending, with the untagged remainder as its own wedge so the ring still
            // covers the window.
            var tagged = data.spendingByTag.map {
                SpendingSlice(
                    id: $0.tagId.uuidString, name: "#\($0.name)", colorHex: $0.color, amount: $0.amount,
                    filter: TransactionFilter(tagIds: [$0.tagId]))
            }
            if data.untaggedSpending > 0 {
                tagged.append(SpendingSlice(id: "untagged", name: "Untagged", amount: data.untaggedSpending))
            }
            all = tagged.stableSorted { $0.amount > $1.amount }
        }

        guard all.count > visibleSlices else { return all }
        let rest = all.dropFirst(visibleSlices).reduce(Decimal(0)) { $0 + $1.amount }
        return Array(all.prefix(visibleSlices)) + [SpendingSlice(id: "other", name: "Other", amount: rest)]
    }
}

/// Where the net worth has been.
nonisolated enum NetWorthSeries {
    struct Point: Identifiable, Equatable, Sendable {
        let month: String
        let value: Double
        var id: String { month }
    }

    /// Skarb stores no historical balances, so the line is walked backwards from today's total
    /// through each month's net — it tracks money in and out, not what holdings did on the market.
    /// Fewer than two months is not a line, so it answers with nothing.
    static func points(netWorth: Decimal, cashflow: [Dashboard.Month]) -> [Point] {
        guard cashflow.count >= 2 else { return [] }
        let nets = cashflow.map { ($0.income - $0.expense - $0.invested as NSDecimalNumber).doubleValue }
        let total = (netWorth as NSDecimalNumber).doubleValue
        return cashflow.enumerated().map { index, month in
            // Everything earned after month `index` has to come back off today's total.
            let after = nets.dropFirst(index + 1).reduce(0, +)
            return Point(month: month.month, value: total - after)
        }
    }
}

nonisolated enum PeriodComparison {
    /// "+12% on the same days last month". The window behind the percentage runs exactly as long
    /// as the one above it, so a month three weeks in is not read against a whole one and reported
    /// as a collapse.
    static func subtitle(value: Decimal, previous: Decimal, period: PeriodKey) -> String {
        guard previous > 0 else { return "nothing to compare with" }
        let diff = ((value - previous) / previous) * 100
        let magnitude = abs((diff as NSDecimalNumber).doubleValue).rounded()
        return "\(diff >= 0 ? "+" : "−")\(Int(magnitude))% \(period.comparison)"
    }
}
