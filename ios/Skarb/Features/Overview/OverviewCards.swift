import Charts
import SwiftUI

// MARK: - Net worth trend

struct NetWorthTrend: View {
    let data: Dashboard

    var body: some View {
        let points = NetWorthSeries.points(netWorth: data.netWorth, cashflow: data.cashflow)
        if points.count >= 2 {
            let values = points.map(\.value)
            let low = values.min() ?? 0
            let high = values.max() ?? 0
            let pad = max(high - low, abs(high), 1) * 0.35

            VStack(spacing: 4) {
                Chart(points) { point in
                    AreaMark(x: .value("Month", Format.monthLabel(point.month)), y: .value("Net worth", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.linearGradient(
                            colors: [Palette.accent.opacity(0.25), Palette.accent.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Month", Format.monthLabel(point.month)), y: .value("Net worth", point.value))
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
            .accessibilityElement()
            .accessibilityLabel("Net worth over the last \(points.count) months")
        }
    }
}

// MARK: - Where it went

struct SpendingCard: View {
    let data: Dashboard
    @Binding var breakdown: Breakdown
    var open: (TransactionFilter) -> Void

    var body: some View {
        let slices = SpendingBreakdown.slices(data, by: breakdown)
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Where it went", subtitle: Format.range(data.period.start, data.period.end))

                SegmentedPills(
                    options: Breakdown.allCases.map { ($0, $0.label) },
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
}

private extension SpendingSlice {
    var color: Color { colorHex.map(HSL.swatch) ?? Palette.uncategorized }
}

private struct Donut: View {
    let slices: [SpendingSlice]
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
        .accessibilityElement()
        .accessibilityLabel("Spending \(windowName), \(Format.money(total, currency))")
    }
}

/// A legend line. Accounts, tags and categories all open the transactions behind them.
private struct SliceRow: View {
    let slice: SpendingSlice
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

    private struct Bar: Identifiable {
        let month: String
        let series: String
        let amount: Double
        var id: String { "\(month)-\(series)" }
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
///
/// Every institution's holding, summed, is the net worth the hero dots over — so the figures here
/// answer to the same switch. The shares don't: a percentage of a hidden total reveals nothing,
/// and it is what keeps the card readable at a glance.
struct AccountsSummaryCard: View {
    let rows: [Dashboard.AccountBalance]
    let currency: String
    @State private var expanded: String?

    var body: some View {
        if !rows.isEmpty {
            let groups = AccountGrouping.byHolding(rows)
            let totals = groups.map(AccountGrouping.total)
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    CardHeader(title: "Accounts")

                    ForEach(groups) { group in
                        groupRow(group, share: AccountGrouping.share(of: AccountGrouping.total(group), among: totals))
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

    private func groupRow(_ group: InstitutionGroup<Dashboard.AccountBalance>, share: String?) -> some View {
        let isOpen = expanded == group.label
        let color = group.rows.first?.account.color ?? "#91897C"
        return Button {
            withAnimation(.smooth(duration: 0.22)) { expanded = isOpen ? nil : group.label }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: Palette.Radius.tile)
                    .fill(HSL.tint(color))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(AccountGrouping.initials(group.label))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(HSL.swatch(color))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.label)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(group.rows.count == 1
                        ? "\(group.rows[0].account.name) · \(group.rows[0].account.currency)"
                        : "\(group.rows.count) accounts · \(Set(group.rows.map(\.account.currency)).sorted().joined(separator: " · "))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    BalanceText(amount: AccountGrouping.total(group), currency: currency)
                    if let share {
                        Text("\(share) of net worth")
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
                BalanceText(amount: row.account.balance, currency: row.account.currency,
                            font: .system(size: 13.5, weight: .semibold))
                if row.account.currency != currency {
                    HStack(spacing: 0) {
                        Text("≈ ")
                        BalanceText(amount: row.balanceConverted, currency: currency,
                                    font: .system(size: 11), color: Palette.faint)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.faint)
                }
            }
        }
        .padding(.leading, 46)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Recent activity

struct RecentActivityCard: View {
    let recent: [Tx]
    @Environment(AppContainer.self) private var app
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
            TransactionEditor(model: app.makeTransactionEditor(for: tx))
        }
    }
}
