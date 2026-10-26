import Foundation

/// The `skarb://` links the app answers to.
nonisolated enum DeepLink: Equatable, Sendable {
    /// `skarb://transactions?account=<id>&tags=<id>&category=<id>` — the same query the web's
    /// `/transactions` link takes, so a link copied between the two lands on the same list.
    case transactions(TransactionFilter)
    /// A bank authorization coming home; see `EnableBankingHandoff`.
    case enableBanking(EnableBankingHandoff.Outcome)

    init?(_ url: URL) {
        guard url.scheme == EnableBankingHandoff.callbackScheme else { return nil }
        if let outcome = EnableBankingHandoff.outcome(from: url) {
            self = .enableBanking(outcome)
            return
        }
        guard url.host() == "transactions" else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let uuid = { (name: String) in items.first { $0.name == name }?.value.flatMap(UUID.init(uuidString:)) }
        var filter = TransactionFilter()
        filter.accountId = uuid("account")
        filter.categoryId = uuid("category")
        filter.tagIds = items.filter { $0.name == "tags" }.compactMap { $0.value.flatMap(UUID.init(uuidString:)) }
        self = .transactions(filter)
    }
}
