import Charts
import SwiftUI

// MARK: - Net worth trend

/// Where the net worth has been. Skarb does not store historical balances, so the line is
/// walked backwards from today's total through each month's net — it tracks money in and out,
/// not what holdings did on the market.
struct NetWorthTrend: View {
    let data: Dashboard

    private struct Point: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
    }

    private var series: [Point] {
        let months = data.cashflow
        guard months.count >= 2 else { return [] }
        let nets = months.map { ($0.income - $0.expense - $0.invested as NSDecimalNumber).doubleValue }
        let total = (data.netWorth as NSDecimalNumber).doubleValue
        return months.enumerated().map { index, month in
            // Everything earned after month `index` has to come back off today's total.
            let after = nets.dropFirst(index + 1).reduce(0, +)
            return Point(label: Format.monthLabel(month.month), value: total - after)
        }
    }

    var body: some View {
        let points = series
        if points.count >= 2 {
            let values = points.map(\.value)
            let low = values.min() ?? 0
            let high = values.max() ?? 0
            let pad = max((high - low), abs(high), 1) * 0.35

            VStack(spacing: 4) {
                Chart(points) { point in
                    AreaMark(x: .value("Month", point.label), y: .value("Net worth", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.linearGradient(
                            colors: [Palette.accent.opacity(0.25), Palette.accent.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Month", point.label), y: .value("Net worth", point.value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(Palette.accent)
                }
                .chartYScale(domain: (low - pad)...(high + pad))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label).font(.system(size: 11)).foregroundStyle(Palette.faint)
                            }
                        }
                    }
                }
                .frame(height: 110)

                Text("Traced back through \(points.count) months of cashflow")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.faint)
            }
            .accessibilityLabel("Net worth over the last \(points.count) months")
        }
    }
}

// MARK: - Where it went

/// One wedge of the spending donut, whichever way the window is broken down.
struct Slice: Identifiable, Equatable {
    let id: String
    var name: String
    var color: Color
    var amount: Decimal
    /// Where tapping this wedge goes, when there are transactions behind it.
    var filter: TransactionFilter?
    /// The longer form of the name, for a legend line too narrow to hold it.
    var hint: String?
}

struct SpendingCard: View {
    let data: Dashboard
    @Binding var breakdown: OverviewScreen.Breakdown
    var open: (TransactionFilter) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Where it went", subtitle: Format.range(data.period.start, data.period.end))

                SegmentedPills(
                    options: OverviewScreen.Breakdown.allCases.map { ($0, $0.label) },
                    selection: $breakdown,
                    accessibilityLabel: "Break spending down by")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)

                if breakdown == .tag && data.spendingByTag.isEmpty {
                    EmptyNote(text: "Nothing tagged \(data.period.key.phrase). Tags are free-form labels — open a transaction to add one.")
                } else if slices.isEmpty {
                    EmptyNote(text: "Nothing spent \(data.period.key.phrase).")
                } else {
                    Donut(slices: slices, total: data.totals.expense, currency: data.currency,
                          windowName: data.period.key.name)
                        .frame(height: 210)
                        .padding(.vertical, 10)

                    VStack(spacing: 10) {
                        ForEach(slices) { slice in
                            SliceRow(slice: slice, currency: data.currency, open: open)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                }

                if breakdown == .tag && data.multiTagCount > 0 {
                    Text("""
                        \(data.multiTagCount) transaction\(data.multiTagCount == 1 ? "" : "s") in this \
                        window carr\(data.multiTagCount == 1 ? "ies" : "y") more than one tag, so these \
                        slices overlap.
                        """)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.faint)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// Six wedges plus an "Other" catch-all — more than that and the ring stops being readable.
    private var slices: [Slice] {
        let all: [Slice]
        switch breakdown {
        case .category:
            all = data.spendingByCategory.map {
                Slice(id: $0.categoryId?.uuidString ?? "uncategorized", name: $0.name,
                      color: HSL.swatch($0.color), amount: $0.amount,
                      filter: $0.categoryId.map { id in TransactionFilter(categoryId: id) })
            }
        case .account:
            // Which account the window left from. The legend is narrow, so the account name
            // carries the line and the bank rides along underneath.
            all = data.spendingByAccount.map {
                Slice(id: $0.accountId.uuidString, name: $0.name, color: HSL.swatch($0.color),
                      amount: $0.amount, filter: TransactionFilter(accountId: $0.accountId),
                      hint: $0.bank.isEmpty ? nil : $0.bank)
            }
        case .tag:
            // Tagged spending, with the untagged remainder as its own wedge so the ring still
            // covers the window.
            var tagged = data.spendingByTag.map {
                Slice(id: $0.tagId.uuidString, name: "#\($0.name)", color: HSL.swatch($0.color),
                      amount: $0.amount, filter: TransactionFilter(tagIds: [$0.tagId]))
            }
            if data.untaggedSpending > 0 {
                tagged.append(Slice(id: "untagged", name: "Untagged",
                                    color: Palette.uncategorized, amount: data.untaggedSpending))
            }
            all = tagged.sorted { $0.amount > $1.amount }
        }

        guard all.count > 6 else { return all }
        let rest = all.dropFirst(6).reduce(Decimal(0)) { $0 + $1.amount }
        return Array(all.prefix(6)) + [
            Slice(id: "other", name: "Other", color: Palette.uncategorized, amount: rest)
        ]
    }
}

private struct Donut: View {
    let slices: [Slice]
    let total: Decimal
    let currency: String
    let windowName: String

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Amount", (slice.amount as NSDecimalNumber).doubleValue),
                innerRadius: .ratio(0.66),
                angularInset: 1.6)
                .cornerRadius(3)
                .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 3) {
                Text(windowName).font(.system(size: 11)).foregroundStyle(Palette.faint)
                Text(Format.money(total, currency, decimals: 0))
                    .font(.display(21))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.horizontal, 30)
        }
        .accessibilityLabel("Spending \(windowName), \(Format.money(total, currency))")
    }
}

/// A legend line. Accounts, tags and categories all open the transactions behind them.
private struct SliceRow: View {
    let slice: Slice
    let currency: String
    var open: (TransactionFilter) -> Void

    var body: some View {
        let row = HStack(spacing: 10) {
            Circle().fill(slice.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(slice.name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                if let hint = slice.hint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Money(amount: slice.amount, currency: currency, font: .system(size: 13.5, weight: .semibold))
            if slice.filter != nil { DisclosureChevron().opacity(0.6) }
        }

        if let filter = slice.filter {
            Button { open(filter) } label: { row.contentShape(.rect) }
                .buttonStyle(.plain)
        } else {
            row
        }
    }
}

// MARK: - In and out

struct CashflowCard: View {
    let months: [Dashboard.Month]
    let currency: String

    private struct Bar: Identifiable {
        let id = UUID()
        let month: String
        let series: String
        let amount: Double
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "In and out", subtitle: "Last \(months.count) months, always up to today") {
                    HStack(spacing: 12) {
                        legend("Earned", Palette.income)
                        legend("Spent", Palette.spend)
                    }
                }

                Chart(bars) { bar in
                    BarMark(
                        x: .value("Month", bar.month),
                        y: .value("Amount", bar.amount),
                        width: 12)
                        .position(by: .value("Series", bar.series))
                        .cornerRadius(4)
                        .foregroundStyle(by: .value("Series", bar.series))
                }
                .chartForegroundStyleScale(["Earned": Palette.income, "Spent": Palette.spend])
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label).font(.system(size: 12)).foregroundStyle(Palette.faint)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Palette.line)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(Format.compact(Decimal(amount)))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.faint)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
    }

    private var bars: [Bar] {
        months.flatMap { month -> [Bar] in
            let label = Format.monthLabel(month.month)
            return [
                Bar(month: label, series: "Earned", amount: (month.income as NSDecimalNumber).doubleValue),
                Bar(month: label, series: "Spent", amount: (month.expense as NSDecimalNumber).doubleValue),
            ]
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }
}

// MARK: - Accounts, grouped

/// Where the net worth sits, grouped by institution: a handful of readable lines whether you
/// hold three accounts or thirty. Individual accounts stay one tap away.
struct AccountsSummaryCard: View {
    let rows: [Dashboard.AccountBalance]
    let currency: String
    @State private var expanded: String?

    private struct Group: Identifiable {
        var id: String { label }
        let label: String
        let color: String
        var total: Decimal
        var rows: [Dashboard.AccountBalance]
    }

    var body: some View {
        if !rows.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    CardHeader(title: "Accounts")

                    ForEach(groups) { group in
                        groupRow(group)
                        if expanded == group.label {
                            ForEach(group.rows) { row in
                                accountLine(row)
                            }
                            .padding(.bottom, 4)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func groupRow(_ group: Group) -> some View {
        let isOpen = expanded == group.label
        let single = group.rows.count == 1
        return Button {
            withAnimation(.smooth(duration: 0.22)) { expanded = isOpen ? nil : group.label }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: Palette.Radius.tile)
                    .fill(HSL.tint(group.color))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(initials(group.label))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(HSL.swatch(group.color))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.label)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(single
                        ? "\(group.rows[0].account.name) · \(group.rows[0].account.currency)"
                        : "\(group.rows.count) accounts · \(Set(group.rows.map(\.account.currency)).sorted().joined(separator: " · "))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Money(amount: group.total, currency: currency)
                    if positiveTotal > 0 {
                        Text("\(sharePct(group.total)) of net worth")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Palette.faint)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.faint)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    private func accountLine(_ row: Dashboard.AccountBalance) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.account.name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                if let tail = row.account.tail {
                    Text(tail).font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Money(amount: row.account.balance, currency: row.account.currency,
                      font: .system(size: 13.5, weight: .semibold))
                if row.account.currency != currency {
                    Text("≈ \(Format.money(row.balanceConverted, currency))")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.faint)
                }
            }
        }
        .padding(.leading, 46)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
    }

    /// Only what you own gets a share of the total — an account in the red takes no width.
    private var positiveTotal: Decimal {
        groups.reduce(Decimal(0)) { $0 + max($1.total, 0) }
    }

    /// A holding that exists shouldn't read as 0% — small shares round up to "<1%".
    private func sharePct(_ total: Decimal) -> String {
        guard positiveTotal > 0 else { return "" }
        let pct = ((max(total, 0) / positiveTotal) * 100 as NSDecimalNumber).doubleValue
        if pct > 0 && pct < 1 { return "<1%" }
        return "\(Int(pct.rounded()))%"
    }

    /// Two letters is enough to tell PKO BP from Monobank at a glance.
    private func initials(_ label: String) -> String {
        let words = label.split(separator: " ")
        let text = words.count > 1
            ? String(words[0].prefix(1)) + String(words[1].prefix(1))
            : String(label.prefix(2))
        return text.uppercased()
    }

    /// Biggest holdings first; inside a group the account order from the API is kept.
    private var groups: [Group] {
        var byLabel: [String: Group] = [:]
        var order: [String] = []
        for row in rows {
            let label = row.account.bankLabel
            if byLabel[label] == nil {
                byLabel[label] = Group(label: label, color: row.account.color, total: 0, rows: [])
                order.append(label)
            }
            byLabel[label]?.total += row.balanceConverted
            byLabel[label]?.rows.append(row)
        }
        return order.compactMap { byLabel[$0] }.sorted { $0.total > $1.total }
    }
}

// MARK: - Recent activity

struct RecentActivityCard: View {
    let recent: [Tx]
    @State private var editing: Tx?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    title: "Recent activity",
                    subtitle: recent.isEmpty ? nil : "Latest \(recent.count), whenever they happened")

                if recent.isEmpty {
                    EmptyNote(text: "No transactions yet. Connect a bank in Settings or add one manually.")
                } else {
                    ForEach(recent) { tx in
                        TransactionRow(tx: tx) { editing = tx }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .sheet(item: $editing) { tx in
            TransactionEditor(tx: tx)
        }
    }
}
