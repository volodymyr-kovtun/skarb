import SwiftUI

@Observable
final class OverviewModel {
    private(set) var data: Dashboard?
    private(set) var error: String?
    var breakdown: Breakdown = .category

    private let service: any LedgerService

    init(service: any LedgerService) {
        self.service = service
    }

    func load(currency: String, period: PeriodKey) async {
        do {
            data = try await service.dashboard(currency: currency.isEmpty ? nil : currency, period: period)
            error = nil
        } catch {
            guard !error.isCancellation else { return }
            // Keep the previous figures on screen while a switch is in flight; only a first load
            // with nothing to show falls back to the message.
            if data == nil { self.error = error.localizedDescription }
        }
    }
}

extension AppContainer {
    func makeOverview() -> OverviewModel { OverviewModel(service: ledgerService) }
}

/// The overview: what everything adds up to, what the chosen window did to it, and where the
/// money went. Same figures, same wording and the same window control as the web dashboard —
/// stacked for a phone instead of spread across a grid.
struct OverviewScreen: View {
    @State private var model: OverviewModel
    @Environment(LedgerStore.self) private var ledger
    @AppStorage(Prefs.currencyKey) private var currency = ""
    @AppStorage(Prefs.periodKey) private var period = PeriodKey.month
    @State private var openingTransactions: TransactionFilter?

    init(model: OverviewModel) { _model = State(initialValue: model) }

    var body: some View {
        SkarbScreen(title: "Overview") {
            if let data = model.data {
                content(data)
            } else if let error = model.error {
                Card { EmptyNote(text: error) }
            } else {
                Card { EmptyNote(text: "Loading your money…") }
            }
        }
        // Reloads on the window, the currency, and after any mutation anywhere in the app.
        .task(id: "\(period.rawValue)|\(currency)|\(ledger.revision)") {
            await model.load(currency: currency, period: period)
        }
    }

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
            VStack(alignment: .leading, spacing: 4) {
                MicroLabel(data.period.key.name)
                Text(Format.range(data.period.start, data.period.end))
                    .font(.system(size: 13.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
            }
            SegmentedPills(
                options: PeriodKey.allCases.map { ($0, $0.short) },
                selection: $period,
                accessibilityLabel: "Report over")
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)

        StatGrid(data: data)

        SpendingCard(data: data, breakdown: $model.breakdown) { openingTransactions = $0 }

        CashflowCard(months: data.cashflow)

        AccountsSummaryCard(rows: data.accounts, currency: data.currency)

        RecentActivityCard(recent: data.recent)
    }
}

// MARK: - Net worth

private struct NetWorthCard: View {
    let data: Dashboard
    @Binding var currency: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    MicroLabel("Net worth")
                    BalanceToggle()
                    Spacer(minLength: 8)
                    if data.availableCurrencies.count > 1 {
                        SegmentedPills(
                            options: data.availableCurrencies.map { ($0, $0) },
                            selection: $currency,
                            accessibilityLabel: "Display currency")
                            .frame(maxWidth: 170)
                    }
                }

                BalanceText(amount: data.netWorth, currency: data.currency, font: .display(42))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 12)

                netSentence
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
                    .padding(.top, 10)

                // The curve stays drawn while balances are hidden: with no axis on it, the shape
                // says how the months went without saying what they came to.
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
                label: "Earned", value: data.totals.income, currency: cur, tone: Palette.income,
                subtitle: PeriodComparison.subtitle(value: data.totals.income, previous: data.previous.income, period: shown),
                hint: comparedWith)
            StatTile(
                label: "Spent", value: data.totals.expense, currency: cur, tone: Palette.spend,
                subtitle: PeriodComparison.subtitle(value: data.totals.expense, previous: data.previous.expense, period: shown),
                hint: comparedWith)
            StatTile(
                label: "Invested", value: data.totals.invested, currency: cur, tone: Palette.accent,
                subtitle: "\(Format.money(data.allTimeInvested, cur, decimals: 0)) all time")
            StatTile(
                label: "Net", value: data.totals.net, currency: cur,
                tone: data.totals.net >= 0 ? Palette.income : Palette.ink,
                subtitle: "after spending & investing", signed: true)
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: Decimal
    let currency: String
    let tone: Color
    let subtitle: String
    /// The comparison window's own dates, for anyone who wants them exactly.
    var hint: String?
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
        .accessibilityHint(hint ?? "")
    }
}
