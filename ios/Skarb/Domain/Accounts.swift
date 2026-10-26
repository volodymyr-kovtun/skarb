import Foundation

/// The currencies a manual account or a cash wallet can be opened in — `CURRENCIES` on the web.
nonisolated enum Currencies {
    static let offered = ["PLN", "UAH", "EUR", "USD", "GBP", "CZK", "CHF"]
}

/// Accounts gathered under the institution that holds them.
nonisolated struct InstitutionGroup<Row>: Identifiable {
    let label: String
    var rows: [Row]
    var id: String { label }
}

nonisolated enum AccountGrouping {
    /// One section per institution, the busiest first — the Accounts page stays short as accounts
    /// pile up. Ties keep the order the API listed them in, so sections don't trade places between
    /// two renders of the same data.
    static func byInstitution(_ accounts: [Account]) -> [InstitutionGroup<Account>] {
        grouped(accounts, label: \.bankLabel).stableSorted { $0.rows.count > $1.rows.count }
    }

    /// Where the net worth sits, biggest holding first — the overview's accounts card.
    static func byHolding(_ rows: [Dashboard.AccountBalance]) -> [InstitutionGroup<Dashboard.AccountBalance>] {
        grouped(rows, label: \.account.bankLabel).stableSorted { total($0) > total($1) }
    }

    static func total(_ group: InstitutionGroup<Dashboard.AccountBalance>) -> Decimal {
        group.rows.reduce(Decimal(0)) { $0 + $1.balanceConverted }
    }

    /// Only meaningful when a group holds a single currency — there are no exchange rates on the
    /// Accounts page, and a sum across currencies would be a number about nothing.
    static func singleCurrencyTotal(_ accounts: [Account]) -> (currency: String, total: Decimal)? {
        let currencies = Set(accounts.map(\.currency))
        guard currencies.count == 1, let currency = currencies.first else { return nil }
        return (currency, accounts.reduce(Decimal(0)) { $0 + $1.balance })
    }

    /// A group's share of everything owned. Only what you own gets a share: an account in the red
    /// takes no width, and a holding that exists never reads as 0% — small ones round up to "<1%".
    static func share(of total: Decimal, among totals: [Decimal]) -> String? {
        let positive = totals.reduce(Decimal(0)) { $0 + max($1, 0) }
        guard positive > 0 else { return nil }
        let pct = ((max(total, 0) / positive) * 100 as NSDecimalNumber).doubleValue
        if pct > 0 && pct < 1 { return "<1%" }
        return "\(Int(pct.rounded()))%"
    }

    /// Two letters is enough to tell PKO BP from Monobank at a glance.
    static func initials(_ label: String) -> String {
        let words = label.split(separator: " ")
        let text = words.count > 1
            ? String(words[0].prefix(1)) + String(words[1].prefix(1))
            : String(label.prefix(2))
        return text.uppercased()
    }

    static func providerLabel(_ provider: String) -> String {
        switch provider {
        case ProviderName.manual: "Manual"
        case ProviderName.monobank, ProviderName.enableBanking: "Auto-synced"
        default: provider
        }
    }

    /// The line under an institution's name on the Accounts page.
    static func subtitle(for group: InstitutionGroup<Account>) -> String {
        let count = group.rows.count
        if group.rows.allSatisfy(\.isCash) {
            return "\(count) wallet\(count == 1 ? "" : "s") · one per currency"
        }
        var text = "\(count) account\(count == 1 ? "" : "s")"
        let providers = Set(group.rows.map(\.provider))
        if providers.count == 1, let provider = providers.first { text += " · \(providerLabel(provider))" }
        return text
    }

    /// The line under an account's name on the Accounts page.
    static func subtitle(for account: Account, in group: InstitutionGroup<Account>) -> String {
        // A wallet is already named after its currency; say what it is for instead.
        var parts = [account.isCash ? "Cash on hand · withdrawals land here" : account.currency]
        if let tail = account.tail { parts.append(tail) }
        if Set(group.rows.map(\.provider)).count > 1 { parts.append(providerLabel(account.provider)) }
        if let threshold = account.lowBalanceThreshold {
            parts.append("alert < \(Format.money(threshold, account.currency, decimals: 0))")
        }
        return parts.joined(separator: " · ")
    }

    private static func grouped<Row>(_ rows: [Row], label: (Row) -> String) -> [InstitutionGroup<Row>] {
        var groups: [InstitutionGroup<Row>] = []
        var index: [String: Int] = [:]
        for row in rows {
            let key = label(row)
            if let at = index[key] {
                groups[at].rows.append(row)
            } else {
                index[key] = groups.count
                groups.append(InstitutionGroup(label: key, rows: [row]))
            }
        }
        return groups
    }
}

/// One wallet per currency, archived ones included — archiving is how a currency opts out, and a
/// fresh wallet beside an archived one would quietly undo that.
nonisolated enum CashWallets {
    static func currencies(in accounts: [Account]) -> [String] {
        accounts.filter(\.isCash).map(\.currency)
    }

    /// The offered currencies that have no wallet yet.
    static func freeCurrencies(in accounts: [Account]) -> [String] {
        let taken = Set(currencies(in: accounts))
        return Currencies.offered.filter { !taken.contains($0) }
    }

    /// Offered only where it can succeed: on a manual account (a synced one reports a bank's
    /// balance), and only while its currency has no wallet — or this account is that wallet.
    static func canToggleWallet(_ account: Account, among accounts: [Account]) -> Bool {
        account.isManual && (account.isCash || !currencies(in: accounts).contains(account.currency))
    }
}

nonisolated enum AccountCopy {
    static func deleteWarning(_ account: Account) -> String {
        // A synced account is rediscovered every sync, so deleting one also tells its connection
        // to skip it from now on — say so, and say where that can be undone.
        if account.connectionId != nil {
            return "Delete “\(account.name)” and all its transactions? It stops syncing and won't "
                + "come back on its own — Settings can bring it back later."
        }
        // Deleting is not the off switch, and the difference is worth a sentence: the next
        // withdrawal would open a fresh wallet, where an archived one keeps the currency out.
        if account.isCash {
            return "Delete your \(account.currency) cash wallet and everything in it? Withdrawals that "
                + "were moved here go back to counting as spending. To stop tracking "
                + "\(account.currency) cash without losing the history, archive it instead."
        }
        return "Delete “\(account.name)” and all its transactions? This cannot be undone."
    }
}

extension Array {
    /// `sorted(by:)` that keeps equal elements in their original order, which the standard
    /// library does not promise.
    nonisolated func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated()
            .sorted { a, b in
                if areInIncreasingOrder(a.element, b.element) { return true }
                if areInIncreasingOrder(b.element, a.element) { return false }
                return a.offset < b.offset
            }
            .map(\.element)
    }
}
