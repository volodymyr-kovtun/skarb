import Foundation
import Observation

/// What the app is right now. The whole UI hangs off this, so there is a single place where
/// "is anyone home?" gets answered — the same job `AuthGate` does on the web.
nonisolated enum AuthPhase: Equatable, Sendable {
    case loading
    case unreachable(String)
    /// The instance has never been claimed; the setup flow claims it with the server's token.
    case setupRequired
    case signedOut
    case signedIn(email: String?)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

/// Who is signed in. Knows nothing about the ledger or syncing — the container listens to
/// `onChange` and starts or stops those, so this stays about one thing.
@Observable
final class SessionStore {
    private(set) var phase: AuthPhase = .loading

    /// Told about every change of phase, after it happens.
    @ObservationIgnored var onChange: ((AuthPhase) -> Void)?

    private let auth: any AuthService
    @ObservationIgnored private var revalidating = false

    init(auth: any AuthService) {
        self.auth = auth
    }

    var email: String? {
        if case .signedIn(let email) = phase { return email }
        return nil
    }

    func load() async {
        do {
            let session = try await auth.session()
            if session.setupRequired {
                set(.setupRequired)
            } else {
                set(session.authenticated ? .signedIn(email: session.email) : .signedOut)
            }
        } catch is UnauthorizedError {
            set(.signedOut)
        } catch {
            set(.unreachable(error.localizedDescription))
        }
    }

    /// Back to the splash and ask again — after the server address changed, say.
    func reload() async {
        set(.loading)
        await load()
    }

    /// A request came back 401. That is usually a lapsed session, but a wrong *current* password
    /// on the change-password form is a 401 too, and signing out over a typo would be absurd. So,
    /// like the web, ask the server: only when it agrees that nobody is signed in does the app
    /// drop to the sign-in screen. A failure to ask changes nothing.
    func revalidate() async {
        guard phase.isSignedIn, !revalidating else { return }
        revalidating = true
        defer { revalidating = false }
        guard let session = try? await auth.session() else { return }
        if !session.authenticated { set(session.setupRequired ? .setupRequired : .signedOut) }
    }

    func signOut() async {
        try? await auth.logout()
        set(.signedOut)
    }

    private func set(_ next: AuthPhase) {
        guard next != phase else { return }
        phase = next
        onChange?(next)
    }
}
