import SwiftUI

/// The overview: what everything adds up to, what the chosen window did to it, and where the
/// money went. Same figures, same wording and the same window control as the web dashboard —
/// stacked for a phone instead of spread across a grid.
struct OverviewScreen: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.currencyKey) private var currency = ""
    @AppStorage(Prefs.periodKey) private var period = PeriodKey.month

    @State private var data: Dashboard?
    @State private var breakdown: Breakdown = .category
    @State private var error: String?
    @State private var openingTransactions: TransactionFilter?

    enum Breakdown: String, Hashable, CaseIterable {
        case category, account, tag

        var label: String {
            switch self {
            case .category: "Categories"
            case .account: "Accounts"
            case .tag: "Tags"
            }
        }
    }

    var body: some View {
        SkarbScreen(title: "Overview") {
            if let data {
                content(data)
            } else if let error {
                Card { EmptyNote(text: error) }
            } else {
                Card { EmptyNote(text: "Loading your money…") }
            }
        }
        // Reloads on the window, the currency, and after any mutation anywhere in the app.
        .task(id: reloadKey) { await load() }
    }

    private var reloadKey: String { "\(period.rawValue)|\(currency)|\(model.revision)" }

    @ViewBuilder
    private func content(_ data: Dashboard) -> some View {
        // The destination has to be registered from inside the stack `SkarbScreen` owns, and
        // exactly once — hence an anchor rather than hanging it off whichever card is handy.
        Color.clear.frame(height: 0)
            .navigationDestination(item: $openingTransactions) { filter in
                FilteredTransactionsScreen(title: "Transactions", filter: filter)
            }

        NetWorthCard(data: data, currency: $currency)

        // The window the tiles and the breakdown below are counted over, and the control that
        // moves it. The dates are spelled out because the pill alone doesn't say whether
        // "this month" means the whole of it.
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    MicroLabel(data.period.key.name)
                    Text(Format.range(data.period.start, data.period.end))
                        .font(.system(size: 13.5))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            SegmentedPills(
                options: PeriodKey.allCases.map { ($0, $0.short) },
                selection: $period,
                accessibilityLabel: "Report over")
        }
        .padding(.horizontal, 4)

        StatGrid(data: data)

        SpendingCard(data: data, breakdown: $breakdown) { filter in
            openingTransactions = filter
        }

        CashflowCard(months: data.cashflow, currency: data.currency)

        AccountsSummaryCard(rows: data.accounts, currency: data.currency)

        RecentActivityCard(recent: data.recent)
    }

    private func load() async {
        do {
            data = try await APIClient.shared.dashboard(
                currency: currency.isEmpty ? nil : currency, period: period)
            error = nil
        } catch {
            model.handle(error)
            // Keep the previous figures on screen while a switch is in flight; only a first
            // load with nothing to show falls back to the message.
            if data == nil { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Net worth

private struct NetWorthCard: View {
    let data: Dashboard
    @Binding var currency: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    MicroLabel("Net worth")
                    Spacer(minLength: 8)
                    if data.availableCurrencies.count > 1 {
                        SegmentedPills(
                            options: data.availableCurrencies.map { ($0, $0) },
                            selection: $currency,
                            accessibilityLabel: "Display currency")
                            .frame(maxWidth: 190)
                    }
                }

                Text(Format.money(data.netWorth, data.currency))
                    .font(.display(42))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 12)

                netSentence
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
                    .padding(.top, 10)

                NetWorthTrend(data: data)
                    .padding(.top, 16)
            }
            .padding(20)
        }
        .onAppear {
            // The server decides what "base" means; once it has answered, the switcher should
            // show the currency actually in use rather than an empty pill.
            if currency.isEmpty { currency = data.currency }
        }
    }

    @ViewBuilder
    private var netSentence: some View {
        let phrase = data.period.key.phrase
        if data.totals.net == 0 {
            Text("Flat \(phrase).")
        } else {
            let figure = Text(Format.money(data.totals.net, data.currency, signed: true))
                .fontWeight(.bold)
                .foregroundStyle(data.totals.net > 0 ? Palette.income : Palette.ink)
            Text("\(figure) left \(phrase), after everything you spent and invested.")
        }
    }
}

// MARK: - Window tiles

private struct StatGrid: View {
    let data: Dashboard

    var body: some View {
        let cur = data.currency
        let shown = data.period.key
        let comparedWith = "Measured against \(Format.range(data.period.previousStart, data.period.previousEnd))"

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(
                label: "Earned", value: data.totals.income, previous: data.previous.income,
                currency: cur, tone: Palette.income, compare: shown.comparison, compareTitle: comparedWith)
            StatTile(
                label: "Spent", value: data.totals.expense, previous: data.previous.expense,
                currency: cur, tone: Palette.spend, compare: shown.comparison, compareTitle: comparedWith)
            StatTile(
                label: "Invested", value: data.totals.invested, previous: nil,
                currency: cur, tone: Palette.accent,
                footer: "\(Format.money(data.allTimeInvested, cur, decimals: 0)) all time")
            StatTile(
                label: "Net", value: data.totals.net, previous: nil, currency: cur,
                tone: data.totals.net >= 0 ? Palette.income : Palette.ink,
                footer: "after spending & investing", signed: true)
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: Decimal
    var previous: Decimal?
    let currency: String
    let tone: Color
    /// How the comparison window relates to this one — "on the same days last month".
    var compare: String?
    /// The comparison window's own dates, for anyone who wants them exactly.
    var compareTitle: String?
    var footer: String?
    var signed = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel(label)
                Text(Format.money(value, currency, signed: signed))
                    .font(.display(24))
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(compareTitle ?? "")
    }

    /// The window behind this percentage runs exactly as long as the one above it, so a month
    /// three weeks in is not read against a whole one and reported as a collapse.
    private var subtitle: String {
        if let footer { return footer }
        guard let previous, previous > 0, let compare else { return "nothing to compare with" }
        let diff = ((value - previous) / previous) * 100
        let magnitude = abs((diff as NSDecimalNumber).doubleValue).rounded()
        return "\(diff >= 0 ? "+" : "−")\(Int(magnitude))% \(compare)"
    }
}
