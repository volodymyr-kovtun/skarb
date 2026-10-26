import SwiftUI

/// Every account, one section per institution — the page stays short as accounts pile up. Cash
/// wallets gather under their own heading, one per currency.
///
/// The one place an excluded account still shows its balance, and every balance here answers to
/// the hide switch.
struct AccountsScreen: View {
    @Environment(AppContainer.self) private var app
    @Environment(LedgerStore.self) private var ledger
    @State private var editing: Account?
    @State private var adding: AccountEditorModel.Kind?
    @State private var showArchived = false
    @State private var openingTransactions: TransactionFilter?

    var body: some View {
        let active = ledger.activeAccounts
        let archived = ledger.accounts.filter(\.isArchived)

        SkarbScreen(title: "Accounts") {
            // A destination is registered for the whole stack, so it gets one anchor rather
            // than one per row — repeating it inside the loop registers it dozens of times.
            Color.clear.frame(height: 0)
                .navigationDestination(item: $openingTransactions) { filter in
                    FilteredTransactionsScreen(title: "Transactions", filter: filter)
                }

            if active.isEmpty {
                emptyCard
            } else {
                ForEach(AccountGrouping.byInstitution(active)) { group in
                    groupCard(group)
                }
            }

            if !archived.isEmpty { archivedCard(archived) }
        } extraToolbar: {
            ToolbarItemGroup(placement: .topBarTrailing) {
                BalanceToggle()
                Menu {
                    Button { adding = .account } label: { Label("Manual account", systemImage: "building.columns") }
                    Button { adding = .wallet } label: { Label("Cash wallet", systemImage: "banknote") }
                        .disabled(CashWallets.freeCurrencies(in: ledger.accounts).isEmpty)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add an account")
            }
        }
        .sheet(item: $editing) { AccountEditor(model: app.makeAccountEditor(for: $0)) }
        .sheet(item: $adding) { AccountEditor(model: app.makeAccountEditor(for: nil, startAs: $0)) }
    }

    private var emptyCard: some View {
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
    }

    private func groupCard(_ group: InstitutionGroup<Account>) -> some View {
        let wallets = group.rows.allSatisfy(\.isCash)
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: group.label, subtitle: AccountGrouping.subtitle(for: group)) {
                    if wallets {
                        if !CashWallets.freeCurrencies(in: ledger.accounts).isEmpty {
                            Button("Add currency") { adding = .wallet }
                                .font(.system(size: 13, weight: .semibold))
                        }
                    } else if let sum = AccountGrouping.singleCurrencyTotal(group.rows) {
                        BalanceText(amount: sum.total, currency: sum.currency, font: .system(size: 15, weight: .semibold))
                    }
                }
                ForEach(group.rows) { account in
                    accountRow(account, subtitle: AccountGrouping.subtitle(for: account, in: group))
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func archivedCard(_ archived: [Account]) -> some View {
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
                        accountRow(account, subtitle: "\(account.bankLabel) · \(account.currency)")
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }

    private func accountRow(_ account: Account, subtitle: String) -> some View {
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
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                BalanceText(amount: account.balance, currency: account.currency)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(RowButtonStyle())
        .contextMenu {
            Button {
                openingTransactions = TransactionFilter(accountId: account.id)
            } label: {
                Label("See transactions", systemImage: "list.bullet")
            }
            Button { editing = account } label: { Label("Edit", systemImage: "pencil") }
        }
    }
}
