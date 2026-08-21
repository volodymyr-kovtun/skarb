import Foundation
import SwiftUI

/// Where the ledger lives. Defaults to the hosted instance; a self-hoster points it elsewhere
/// from Settings, and changing it drops the session cookie of the server being left.
nonisolated enum ServerSettings {
    static let defaultURL = URL(string: "https://skarb.subero.app")!
    private static let key = "skarb.serverURL"

    static var baseURL: URL {
        get {
            UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:)) ?? defaultURL
        }
        set {
            UserDefaults.standard.set(newValue.absoluteString, forKey: key)
        }
    }

    /// Accepts what someone would actually type — `skarb.subero.app`, with or without a scheme
    /// or a trailing slash — and returns the origin the API client should call.
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
}

/// What the app is right now. The whole UI hangs off this, so there is a single place where
/// "is anyone home?" gets answered — the same job `AuthGate` does on the web.
nonisolated enum AuthPhase: Equatable {
    case loading
    case unreachable(String)
    /// The instance has never been claimed. Claiming it needs the setup token from the server
    /// log, which is a desktop job — the phone says so rather than pretending otherwise.
    case setupRequired
    case signedOut
    case signedIn(email: String?)
}

/// The app's shared state: who is signed in, what the ledger's accounts and categories are,
/// and whether a sync is running. Screens read it; mutations bump `revision`, which is the
/// signal every screen reloads on — the small-app equivalent of the web's `refreshAll`.
@Observable
final class AppModel {
    var phase: AuthPhase = .loading
    var meta: Meta?
    var syncRunning: [String] = []
    /// Bumped after every mutation. Screens key their `.task` on it and reload.
    private(set) var revision = 0
    /// A one-line message that slides in over the tab bar — "Synced", "Rule saved".
    var toast: Toast?

    struct Toast: Equatable, Identifiable {
        var id = UUID()
        var message: String
        var isError = false
        /// Set when the action behind this toast can be taken back, e.g. "Undo".
        var undoLabel: String?

        // The work behind the label lives in `undoAction`; identity is all the view needs.
        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    /// What the current toast's undo button runs. Cleared with the toast.
    private var undoAction: (() async -> Void)?

    private var syncPoll: Task<Void, Never>?

    var isSyncing: Bool { !syncRunning.isEmpty }

    var accounts: [Account] { meta?.accounts ?? [] }
    var categories: [Category] { meta?.categories ?? [] }
    var tags: [Tag] { meta?.tags ?? [] }

    // MARK: - Session

    func loadSession() async {
        do {
            let session = try await APIClient.shared.session()
            if session.setupRequired {
                phase = .setupRequired
            } else if session.authenticated {
                phase = .signedIn(email: session.email)
                await loadMeta()
                startSyncPolling()
            } else {
                phase = .signedOut
                meta = nil
                stopSyncPolling()
            }
        } catch is UnauthorizedError {
            phase = .signedOut
        } catch {
            phase = .unreachable(error.localizedDescription)
        }
    }

    func signOut() async {
        try? await APIClient.shared.logout()
        meta = nil
        stopSyncPolling()
        phase = .signedOut
    }

    /// Any request that came back 401 means the cookie lapsed mid-visit; drop straight back
    /// to the sign-in screen rather than leaving broken pages on screen.
    func handle(_ error: Error) {
        if error is UnauthorizedError {
            meta = nil
            stopSyncPolling()
            phase = .signedOut
        }
    }

    func switchServer(to url: URL) async {
        APIClient.shared.clearCookies()
        APIClient.shared.baseURL = url
        meta = nil
        stopSyncPolling()
        phase = .loading
        await loadSession()
    }

    // MARK: - Shared data

    func loadMeta() async {
        do {
            meta = try await APIClient.shared.meta()
        } catch {
            handle(error)
        }
    }

    /// Call after any mutation. Re-reads the shared lists and tells every screen to reload.
    func invalidate() async {
        await loadMeta()
        revision += 1
    }

    func show(_ message: String, isError: Bool = false) {
        undoAction = nil
        toast = Toast(message: message, isError: isError)
    }

    /// A toast with a way back — used where one tap rewrote a pile of transactions.
    func show(_ message: String, undoLabel: String, undo: @escaping () async -> Void) {
        undoAction = undo
        toast = Toast(message: message, undoLabel: undoLabel)
    }

    func runUndo() async {
        let action = undoAction
        dismissToast()
        await action?()
    }

    func dismissToast() {
        undoAction = nil
        toast = nil
    }

    /// Runs `body`, surfaces whatever it throws as a toast, and reports whether it worked.
    @discardableResult
    func perform(_ successMessage: String? = nil, _ body: () async throws -> Void) async -> Bool {
        do {
            try await body()
            await invalidate()
            if let successMessage { show(successMessage) }
            return true
        } catch {
            handle(error)
            show(error.localizedDescription, isError: true)
            return false
        }
    }

    // MARK: - Sync

    func syncNow() async {
        do {
            try await APIClient.shared.syncAll()
            show("Syncing your banks…")
            await refreshSyncStatus()
        } catch {
            handle(error)
            show(error.localizedDescription, isError: true)
        }
    }

    func refreshSyncStatus() async {
        do {
            let status = try await APIClient.shared.syncStatus()
            let wasSyncing = !syncRunning.isEmpty
            syncRunning = status.running
            // A sync that just finished has landed new transactions — everything on screen is
            // one revision out of date.
            if wasSyncing && status.running.isEmpty { await invalidate() }
        } catch {
            handle(error)
        }
    }

    /// Polls while the app is in front: often while a sync runs, rarely when it doesn't —
    /// the same cadence the web uses.
    func startSyncPolling() {
        guard syncPoll == nil else { return }
        syncPoll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshSyncStatus()
                let interval: Duration = self.isSyncing ? .seconds(4) : .seconds(30)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopSyncPolling() {
        syncPoll?.cancel()
        syncPoll = nil
    }
}

// MARK: - Remembered preferences

/// The three choices that outlive a launch, kept in one place so the keys can't drift.
enum Prefs {
    /// Light, dark, or follow the system — the web's theme toggle.
    static let themeKey = "skarb.theme"
    /// The currency every report is read in. Empty means "whatever the server calls base".
    static let currencyKey = "skarb.displayCurrency"
    /// The window the overview reopens on.
    static let periodKey = "skarb.dashboardPeriod"
}

enum ThemeMode: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}
