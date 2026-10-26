import Foundation

/// The server answered 401. Usually the session lapsed, but not always — a wrong *current*
/// password on the change-password form is a 401 too — which is why receiving one makes the app
/// re-check the session rather than sign out on the spot (see `SessionStore.revalidate`).
nonisolated struct UnauthorizedError: LocalizedError {
    var message = "Your session has ended. Please sign in again."
    var errorDescription: String? { message }
}

/// Anything the server refused with a message of its own — a bad token, an expired consent,
/// a rate limit. Its text is written for a person, so it is meant to be shown.
nonisolated struct APIError: LocalizedError {
    var message: String
    var status: Int
    var errorDescription: String? { message }
}

nonisolated enum APIErrorText {
    static func friendly(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: "You're offline."
        case .timedOut: "The server took too long to answer."
        case .cannotFindHost, .cannotConnectToHost: "Couldn't reach that server."
        case .secureConnectionFailed, .serverCertificateUntrusted:
            "The server's certificate wasn't trusted."
        default: error.localizedDescription
        }
    }

    /// Turns a `DecodingError` into something worth reading.
    ///
    /// The overwhelmingly likely cause of one is version skew — the app talking to a Skarb
    /// older than itself, which simply doesn't send a field the app now needs. "Didn't look
    /// like Skarb" sends you off checking the address, which is the one thing that isn't
    /// wrong. So name the field that was missing, and name the fix.
    static func explain(_ error: DecodingError, path: String) -> String {
        func trail(_ context: DecodingError.Context, _ key: CodingKey?) -> String {
            let parts = context.codingPath.map(\.stringValue) + [key?.stringValue].compactMap { $0 }
            let joined = parts.filter { !$0.isEmpty }.joined(separator: ".")
            return joined.isEmpty ? path : joined
        }

        switch error {
        case .keyNotFound(let key, let context):
            return "This server is running an older Skarb than the app expects — "
                + "\(path) came back without “\(trail(context, key))”. "
                + "Deploy the current version, then pull to refresh."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "The server sent “\(trail(context, nil))” in a shape the app didn't expect. "
                + "That usually means the app and the server are different versions."
        case .dataCorrupted:
            return "The server's answer wasn't valid Skarb JSON. Check the address."
        @unknown default:
            return "The server's answer didn't look like Skarb. Check the address."
        }
    }
}

extension Error {
    /// A request the app itself abandoned — a filter changed mid-load, a sheet closed. Never worth
    /// a toast: nothing went wrong, the answer is just no longer wanted.
    nonisolated var isCancellation: Bool {
        if self is CancellationError { return true }
        if let url = self as? URLError, url.code == .cancelled { return true }
        return false
    }
}
