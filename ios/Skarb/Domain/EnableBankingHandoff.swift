import Foundation

/// How a bank authorization started in the app finds its way back to it.
///
/// Enable Banking only redirects to an https URL the owner registered, and the one every owner
/// registered is `/settings` on their server — the web app's. So the app asks the server to mark
/// its authorizations (`client=app`, which puts `app:` in front of the connection id in the OAuth
/// state), opens the bank in a browser sheet listening for `skarb://`, and the web page that the
/// bank lands on hands any `app:` state over to `skarb://enablebanking?…` before it renders. What
/// arrives here is that URL, carrying either a code or the error the bank sent instead.
nonisolated enum EnableBankingHandoff {
    /// What the authorize request names this client as.
    static let client = "app"
    /// The scheme the browser sheet waits for, and the one Info.plist registers.
    static let callbackScheme = "skarb"

    private static let host = "enablebanking"
    private static let statePrefix = "app:"

    enum Outcome: Equatable, Sendable {
        /// The bank said yes: hand the code to the server for this connection.
        case authorized(connection: UUID, code: String)
        /// The bank, or the person, said no — with the reason when there was one.
        case refused(String)
    }

    /// Reads a `skarb://enablebanking?…` URL. Nil for any other URL, so a caller can try this on
    /// every link the app is opened with.
    static func outcome(from url: URL) -> Outcome? {
        guard url.scheme == callbackScheme, url.host() == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value }

        if let error = value("error") {
            let detail = value("error_description") ?? error
            return .refused("The bank didn't grant access: \(detail.replacingOccurrences(of: "_", with: " ")).")
        }
        guard let state = value("state"), state.hasPrefix(statePrefix),
              let connection = UUID(uuidString: String(state.dropFirst(statePrefix.count))),
              let code = value("code"), !code.isEmpty
        else { return .refused("The bank sent back an answer Skarb couldn't read. Try linking again.") }
        return .authorized(connection: connection, code: code)
    }
}
