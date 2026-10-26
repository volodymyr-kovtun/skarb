import Foundation
import Observation

/// Which tab is showing, and what a deep link asked for.
@Observable
final class AppRouter {
    enum Destination: String, Hashable {
        case overview, transactions, accounts, categories, settings
    }

    /// Reopens on the tab you left — a ledger you check twice a day shouldn't reset to the
    /// overview every time.
    var tab: Destination {
        didSet { defaults.set(tab.rawValue, forKey: Prefs.tabKey) }
    }

    /// A filter a link asked the Activity tab to open on. The tab takes it and clears it.
    var pendingActivityFilter: TransactionFilter?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tab = defaults.string(forKey: Prefs.tabKey).flatMap(Destination.init(rawValue:)) ?? .overview
    }

    func show(_ filter: TransactionFilter) {
        pendingActivityFilter = filter
        tab = .transactions
    }

    func takeActivityFilter() -> TransactionFilter? {
        defer { pendingActivityFilter = nil }
        return pendingActivityFilter
    }
}
