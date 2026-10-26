import Foundation
import Observation

/// Whether a bank sync is running, and what the recent ones said.
///
/// Syncs run on the server in the background — Monobank's rate limits make one take minutes — so
/// the app polls `/api/sync/status`: often while something runs, rarely when nothing does, and
/// not at all while the app is in someone's pocket.
@Observable
final class SyncMonitor {
    private(set) var running: [String] = []
    private(set) var logs: [SyncStatus.LogEntry] = []

    private let service: any SyncService
    private let ledger: LedgerStore
    private let toasts: ToastCenter
    @ObservationIgnored private var poll: Task<Void, Never>?

    init(service: any SyncService, ledger: LedgerStore, toasts: ToastCenter) {
        self.service = service
        self.ledger = ledger
        self.toasts = toasts
    }

    var isSyncing: Bool { !running.isEmpty }

    func syncAll() async {
        do {
            try await service.syncAll()
            toasts.show("Syncing your banks…")
            await refresh()
        } catch {
            toasts.show(error)
        }
    }

    func sync(_ connection: Connection, full: Bool) async {
        do {
            try await service.sync(connection.id, full: full)
            toasts.show(full ? "Full re-sync started" : "Syncing \(connection.displayName)…")
            await refresh()
        } catch {
            toasts.show(error)
        }
    }

    func refresh() async {
        guard let status = try? await service.status() else { return }
        let wasSyncing = isSyncing
        running = status.running
        logs = status.logs
        // A sync that just finished has landed new transactions — everything on screen is one
        // revision out of date.
        if wasSyncing && !isSyncing { await ledger.invalidate() }
    }

    func start() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.isSyncing ? .seconds(4) : .seconds(30))
            }
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
    }
}
