import Foundation
import Observation

/// The Activity tab: what the list is narrowed to, what is ticked, and what a selection had
/// done to it.
@Observable
final class TransactionsModel {
    /// A category was just changed by hand, and this is what Skarb would make of it. Held here
    /// rather than in the editor so the offer outlives the sheet that produced it.
    struct RuleOffer: Identifiable {
        let id = UUID()
        var tx: Tx
        var category: Category
        var suggestion: RuleSuggestion
    }

    var filter = TransactionFilter()
    /// What is in the search field right now; `applySearch()` is what makes it count.
    var searchText = ""
    private(set) var appliedSearch = ""

    private(set) var selecting = false
    private(set) var selection = BulkSelection()
    private(set) var bulkBusy = false

    var ruleOffer: RuleOffer?

    let list: TransactionPageLoader

    private let transactions: any TransactionService
    private let tags: any TagService
    private let rules: any RuleService
    private let ledger: LedgerStore
    private let toasts: ToastCenter

    init(
        transactions: any TransactionService, tags: any TagService, rules: any RuleService,
        ledger: LedgerStore, toasts: ToastCenter
    ) {
        self.transactions = transactions
        self.tags = tags
        self.rules = rules
        self.ledger = ledger
        self.toasts = toasts
        list = TransactionPageLoader(service: transactions)
    }

    /// The filter the list and "select all" both ask with.
    var activeFilter: TransactionFilter {
        var f = filter
        f.search = appliedSearch
        return f
    }

    var hasNarrowing: Bool { !filter.isEmpty || !searchText.isEmpty }

    func applySearch() { appliedSearch = searchText.trimmed }

    func clearFilters() {
        filter = TransactionFilter()
        searchText = ""
        appliedSearch = ""
    }

    func reload() async { await list.reload(activeFilter) }

    /// A link asked for a particular list. It replaces the filters, search included, so what
    /// opens is exactly what the link named.
    func open(_ filter: TransactionFilter) {
        self.filter = filter
        searchText = filter.search
        appliedSearch = filter.search
        self.filter.search = ""
    }

    // MARK: - Selection

    /// A mode rather than a checkbox on every row: the rows stay one tap from their editor the
    /// rest of the time.
    func startSelecting(with id: UUID? = nil) {
        selecting = true
        if let id, !selection.contains(id) { selection.toggle(id) }
        toasts.clearance = ToastCenter.bulkBarClearance
    }

    func stopSelecting() {
        selecting = false
        selection.clear()
        toasts.clearance = ToastCenter.tabBarClearance
    }

    func toggle(_ tx: Tx) { selection.toggle(tx.id) }

    func toggleDay(_ ids: [UUID]) { selection.toggleAll(ids) }

    /// Everything the current filters match, across every page — the list only ever holds a
    /// page, and a bulk edit that stops at the fold is how half a cleanup gets done.
    func selectAllMatching() async {
        bulkBusy = true
        defer { bulkBusy = false }
        do {
            let result = try await transactions.ids(matching: activeFilter)
            selection.replace(with: result.ids)
            if let note = BulkAction.capNote(selected: result.ids.count, total: result.total) {
                toasts.show(note)
            }
        } catch {
            toasts.show(error)
        }
    }

    /// Applies on the tap that picks it and keeps the selection, so filing forty rows and then
    /// tagging the same forty is two taps rather than two selections. The one edit its opposite
    /// cannot reverse — a category — comes back with an undo.
    func apply(_ action: BulkAction) async {
        guard !selection.isEmpty, !bulkBusy else { return }
        bulkBusy = true
        defer { bulkBusy = false }
        do {
            let result = try await transactions.bulkUpdate(Array(selection.ids), action.patch)
            await ledger.invalidate()
            let message = BulkAction.summary(updated: result.updated, action)
            guard !result.reverts.isEmpty else {
                toasts.show(message)
                return
            }
            let reverts = result.reverts
            toasts.show(message) { [rules, ledger, toasts] in
                do {
                    try await rules.revert(reverts)
                    await ledger.invalidate()
                } catch {
                    toasts.show(error)
                }
            }
        } catch {
            toasts.show(error)
        }
    }

    /// A tag made on the bulk bar goes straight onto the selection.
    func addNewTag(named raw: String) async {
        let name = raw.trimmed.lowercased()
        guard !name.isEmpty else { return }
        do {
            let tag = try await tags.create(name: name, color: nil)
            ledger.remember(tag)
            await apply(.addTag(tag))
        } catch {
            toasts.show(error)
        }
    }

    // MARK: - Rules

    /// After a category is set by hand, ask whether it should become a rule. The save has
    /// already landed, so this is pure upside: if there is nothing worth suggesting, or the
    /// suggestion can't be fetched, the transaction is simply left as corrected.
    func offerRule(for tx: Tx) async {
        guard let category = tx.category,
              let suggestion = try? await transactions.ruleSuggestion(for: tx.id, pattern: nil),
              suggestion.pattern != nil
        else { return }
        ruleOffer = RuleOffer(tx: tx, category: category, suggestion: suggestion)
    }
}

extension AppContainer {
    func makeTransactions() -> TransactionsModel {
        TransactionsModel(transactions: transactions, tags: tags, rules: rules, ledger: ledger, toasts: toasts)
    }
}
