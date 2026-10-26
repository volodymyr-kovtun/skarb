import Foundation
import Observation

/// The composition root: the one place that knows which implementation stands behind each
/// protocol, and the only place a service or a store is constructed.
///
/// Everything below it receives what it needs through its initializer — services as protocols,
/// so a test or a preview can hand in fakes — and nothing reaches for a shared singleton. Views
/// get the container from the environment only to build the view models of the sheets they
/// present; the `make…` factories next to each feature are what do that.
@Observable
final class AppContainer {
    let server: ServerAddress
    let session: SessionStore
    let ledger: LedgerStore
    let toasts: ToastCenter
    let sync: SyncMonitor
    let router: AppRouter

    let auth: any AuthService
    let ledgerService: any LedgerService
    let transactions: any TransactionService
    let accounts: any AccountService
    let categories: any CategoryService
    let tags: any TagService
    let rules: any RuleService
    let connections: any ConnectionService
    let enableBanking: any EnableBankingService
    let notifications: any NotificationService
    let imports: any ImportService

    private let http: URLSessionHTTPClient

    var actions: ActionRunner { ActionRunner(ledger: ledger, toasts: toasts) }

    init(server: ServerAddress = ServerAddress(), defaults: UserDefaults = .standard) {
        let http = URLSessionHTTPClient(server: server)
        self.http = http
        self.server = server

        let auth = LiveAuthService(http: http)
        let ledgerService = LiveLedgerService(http: http)
        self.auth = auth
        self.ledgerService = ledgerService
        transactions = LiveTransactionService(http: http)
        accounts = LiveAccountService(http: http)
        categories = LiveCategoryService(http: http)
        tags = LiveTagService(http: http)
        rules = LiveRuleService(http: http)
        connections = LiveConnectionService(http: http)
        enableBanking = LiveEnableBankingService(http: http)
        notifications = LiveNotificationService(http: http)
        imports = LiveImportService(http: http)

        let toasts = ToastCenter()
        let session = SessionStore(auth: auth)
        let ledger = LedgerStore(service: ledgerService)
        self.toasts = toasts
        self.session = session
        self.ledger = ledger
        sync = SyncMonitor(service: LiveSyncService(http: http), ledger: ledger, toasts: toasts)
        router = AppRouter(defaults: defaults)

        // Every 401 anywhere is one question for the session, asked in one place.
        http.onUnauthorized = { [weak session] in
            Task { await session?.revalidate() }
        }
        session.onChange = { [weak self] phase in self?.sessionChanged(to: phase) }
    }

    // MARK: - Lifecycle

    private func sessionChanged(to phase: AuthPhase) {
        if phase.isSignedIn {
            Task { await ledger.reload() }
            sync.start()
        } else {
            // Nothing from one session may show up in the next.
            ledger.clear()
            sync.stop()
            toasts.dismiss()
        }
    }

    /// Back in front: catch up on whatever happened meanwhile.
    func becameActive() {
        guard session.phase.isSignedIn else { return }
        sync.start()
        Task { await ledger.invalidate() }
    }

    /// Nothing should be polling a server while the app is in someone's pocket.
    func movedToBackground() {
        sync.stop()
    }

    func signOut() async {
        await session.signOut()
        http.clearSessionCookies()
    }

    /// Changing the server drops the session of the one being left, which is why signing in
    /// again is expected afterwards.
    func switchServer(to url: URL) async {
        http.clearSessionCookies()
        server.baseURL = url
        await session.reload()
    }

    // MARK: - Links

    func open(_ url: URL) {
        switch DeepLink(url) {
        case .transactions(let filter):
            router.show(filter)
        case .enableBanking(let outcome):
            // The browser sheet normally catches this itself. If the link reached the app another
            // way — the page opened in Safari instead — it is finished here the same way.
            Task { await finishBankLink(outcome) }
        case nil:
            break
        }
    }

    /// Hands a bank's answer to the server. Shared by the linking sheet and the link handler,
    /// so both finish a link identically.
    @discardableResult
    func finishBankLink(_ outcome: EnableBankingHandoff.Outcome) async -> Bool {
        switch outcome {
        case .refused(let reason):
            toasts.show(reason, isError: true)
            return false
        case .authorized(let connection, let code):
            return await actions.perform("Bank linked — the first sync has started") {
                try await enableBanking.complete(connection, code: code)
            }
        }
    }
}
