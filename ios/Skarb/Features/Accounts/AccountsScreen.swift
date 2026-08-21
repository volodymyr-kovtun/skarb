import SwiftUI

/// Every account, one section per institution — the page stays short as accounts pile up.
struct AccountsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Account?
    @State private var adding = false
    @State private var showArchived = false
    @State private var openingTransactions: TransactionFilter?

    private var active: [Account] { model.accounts.filter { !$0.isArchived } }
    private var archived: [Account] { model.accounts.filter(\.isArchived) }

    var body: some View {
        SkarbScreen(title: "Accounts") {
            // A destination is registered for the whole stack, so it gets one anchor rather
            // than one per row — repeating it inside the loop registers it dozens of times.
            Color.clear.frame(height: 0)
                .navigationDestination(item: $openingTransactions) { filter in
                    FilteredTransactionsScreen(title: "Transactions", filter: filter)
                }

            if active.isEmpty {
                Card {
                    VStack(spacing: 14) {
                        Image(systemName: "building.columns")
                            .font(.system(size: 28))
                            .foregroundStyle(Palette.faint)
                        Text("No accounts yet. Connect a bank in Settings, or add a manual account to track cash.")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 48)
                }
            } else {
                ForEach(groups, id: \.label) { group in
                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            CardHeader(title: group.label, subtitle: subtitle(for: group)) {
                                if let sum = singleCurrencyTotal(group.accounts) {
                                    Money(amount: sum.total, currency: sum.currency,
                                          font: .system(size: 15, weight: .semibold))
                                }
                            }
                            ForEach(group.accounts) { account in
                                accountRow(account)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }

            if !archived.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.smooth(duration: 0.22)) { showArchived.toggle() }
                        } label: {
                            SettingsRow(title: "Archived", subtitle: "\(archived.count) closed account\(archived.count == 1 ? "" : "s")") {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.faint)
                                    .rotationEffect(.degrees(showArchived ? 90 : 0))
                            }
                        }
                        .buttonStyle(RowButtonStyle())

                        if showArchived {
                            ForEach(archived) { account in
                                accountRow(account)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        } extraToolbar: {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add manual account")
            }
        }
        .sheet(item: $editing) { AccountEditor(account: $0) }
        .sheet(isPresented: $adding) { AccountEditor(account: nil) }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            Button { editing = account } label: {
                HStack(spacing: 12) {
                    ColorDot(hex: account.color, size: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(account.name)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if account.isExcluded { Chip(text: "not counted") }
                        }
                        Text(rowSubtitle(account))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.faint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Money(amount: account.balance, currency: account.currency)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(RowButtonStyle())
        }
        .contextMenu {
            Button {
                openingTransactions = TransactionFilter(accountId: account.id)
            } label: {
                Label("See transactions", systemImage: "list.bullet")
            }
            Button { editing = account } label: { Label("Edit", systemImage: "pencil") }
        }
    }

    private func rowSubtitle(_ account: Account) -> String {
        var parts = [account.currency]
        if let tail = account.tail { parts.append(tail) }
        if let threshold = account.lowBalanceThreshold {
            parts.append("alert < \(Format.money(threshold, account.currency, decimals: 0))")
        }
        return parts.joined(separator: " · ")
    }

    private struct Group {
        let label: String
        var accounts: [Account]
    }

    /// One section per institution, the busiest first.
    private var groups: [Group] {
        var byLabel: [String: Group] = [:]
        var order: [String] = []
        for account in active {
            let label = account.bankLabel
            if byLabel[label] == nil {
                byLabel[label] = Group(label: label, accounts: [])
                order.append(label)
            }
            byLabel[label]?.accounts.append(account)
        }
        return order.compactMap { byLabel[$0] }.sorted { $0.accounts.count > $1.accounts.count }
    }

    private func subtitle(for group: Group) -> String {
        let providers = Set(group.accounts.map(\.provider))
        var text = "\(group.accounts.count) account\(group.accounts.count == 1 ? "" : "s")"
        if providers.count == 1, let provider = providers.first {
            text += " · \(Self.providerLabel[provider] ?? provider)"
        }
        return text
    }

    /// Only meaningful when a group holds a single currency — no exchange rates on this screen.
    private func singleCurrencyTotal(_ accounts: [Account]) -> (currency: String, total: Decimal)? {
        let currencies = Set(accounts.map(\.currency))
        guard currencies.count == 1, let currency = currencies.first else { return nil }
        return (currency, accounts.reduce(Decimal(0)) { $0 + $1.balance })
    }

    private static let providerLabel: [String: String] = [
        "manual": "Manual", "monobank": "Auto-synced", "enablebanking": "Auto-synced",
    ]
}
