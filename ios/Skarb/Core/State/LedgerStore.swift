import Foundation
import Observation

/// The lists every screen needs — accounts, categories, tags — and the signal to reload.
///
/// Mutations call `invalidate()`, which re-reads the lists and bumps `revision`; screens key their
/// `.task(id:)` on it. That is the web's `refreshAll` in small: everything reloads on purpose,
/// because a hand-maintained graph of who depends on what is how two screens end up disagreeing.
@Observable
final class LedgerStore {
    private(set) var meta: Meta?
    /// Bumped after every mutation. Screens key their loads on it.
    private(set) var revision = 0

    private let service: any LedgerService

    init(service: any LedgerService) {
        self.service = service
    }

    var accounts: [Account] { meta?.accounts ?? [] }
    var categories: [Category] { meta?.categories ?? [] }
    var tags: [Tag] { meta?.tags ?? [] }

    var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    var walletCurrencies: [String] { CashWallets.currencies(in: accounts) }

    func account(_ id: UUID?) -> Account? { id.flatMap { id in accounts.first { $0.id == id } } }
    func category(_ id: UUID?) -> Category? { id.flatMap { id in categories.first { $0.id == id } } }

    func reload() async {
        // A 401 is handled where every 401 is (the session re-check); anything else leaves the
        // lists as they were rather than blanking every screen over one failed read.
        if let fresh = try? await service.meta() { meta = fresh }
    }

    /// Call after any mutation: re-reads the shared lists and tells every screen to reload.
    func invalidate() async {
        await reload()
        revision += 1
    }

    func clear() { meta = nil }

    /// A tag created inline (in an editor, or on the bulk bar) is usable before the next reload.
    func remember(_ tag: Tag) {
        guard var meta, !meta.tags.contains(where: { $0.id == tag.id }) else { return }
        meta.tags.append(tag)
        self.meta = meta
    }
}
