import Foundation

/// The shape every one-tap mutation has: do it, reload what changed, say how it went.
///
/// Handed to view models instead of the stores themselves, so a model that deletes a tag depends
/// on exactly this and nothing else.
struct ActionRunner {
    let ledger: LedgerStore
    let toasts: ToastCenter

    /// Runs `body`, reloads on success, surfaces whatever it throws as a toast, and reports
    /// whether it worked.
    @discardableResult
    func perform(_ success: String? = nil, _ body: () async throws -> Void) async -> Bool {
        do {
            try await body()
            await ledger.invalidate()
            if let success { toasts.show(success) }
            return true
        } catch {
            toasts.show(error)
            return false
        }
    }
}
