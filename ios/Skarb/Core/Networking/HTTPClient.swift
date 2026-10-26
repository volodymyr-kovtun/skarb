import Foundation

/// The one door to a Skarb server. Services describe requests; this sends them.
///
/// It is a protocol so nothing above it depends on `URLSession`: every service takes an
/// `HTTPClient`, and a test hands them one that records what they asked for.
@MainActor
protocol HTTPClient: AnyObject {
    func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response
}

/// `HTTPClient` over `URLSession`, authenticated the way the web client is.
///
/// The session is the same HttpOnly `skarb.session` cookie the browser carries, kept in the
/// shared cookie jar on disk so it survives a relaunch. Nothing here stores a password or a
/// token; signing out is the server clearing the cookie.
final class URLSessionHTTPClient: HTTPClient {
    private let server: ServerAddress
    private let session: URLSession
    private let cookies: HTTPCookieStorage
    private let decoder = JSONCoding.decoder()
    private let encoder = JSONCoding.encoder()

    /// Called on every 401. Wired by the container to a session re-check, so that one place —
    /// not every screen — decides whether a 401 means the session is gone.
    var onUnauthorized: (() -> Void)?

    init(server: ServerAddress, cookies: HTTPCookieStorage = .shared) {
        self.server = server
        self.cookies = cookies
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookies
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        session = URLSession(
            configuration: config, delegate: LocalhostTrustDelegate(), delegateQueue: nil)
    }

    /// Forgets the session cookie. Used when switching servers — the session belongs to the one
    /// being left — and as a belt-and-braces companion to `POST /api/auth/logout`.
    func clearSessionCookies() {
        for cookie in cookies.cookies ?? [] where cookie.name.hasPrefix("skarb.") {
            cookies.deleteCookie(cookie)
        }
    }

    func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response {
        let urlRequest = try makeURLRequest(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw APIError(message: APIErrorText.friendly(error), status: 0)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "The server sent something unexpected.", status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            // The API answers failures as `{ "error": "..." }`; that text is written for a
            // person, so it is preferred over the status line whenever it is there.
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.error
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized
            if http.statusCode == 401 {
                onUnauthorized?()
                throw UnauthorizedError(message: message)
            }
            throw APIError(message: message, status: http.statusCode)
        }

        if let nothing = NoContent() as? Response { return nothing }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch let error as DecodingError {
            throw APIError(message: APIErrorText.explain(error, path: request.path), status: 0)
        }
    }

    private func makeURLRequest<Response>(_ request: APIRequest<Response>) throws -> URLRequest {
        guard var components = URLComponents(
            url: server.baseURL.appending(path: request.path), resolvingAgainstBaseURL: false)
        else { throw APIError(message: "That server address isn't valid.", status: 0) }
        if !request.query.isEmpty { components.queryItems = request.query }
        guard let url = components.url else {
            throw APIError(message: "That server address isn't valid.", status: 0)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpShouldHandleCookies = true
        if let body = request.body { urlRequest.httpBody = try encoder.encode(body) }
        return urlRequest
    }

    private nonisolated struct ErrorBody: Decodable { var error: String }
}

/// The .NET `localhost` development certificate is self-signed, so a debug build talking to
/// `make run` on the same Mac would otherwise fail the TLS handshake. The exception is narrow
/// on purpose: debug builds only, loopback hosts only. Release builds validate normally.
private final class LocalhostTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        #if DEBUG
        let host = challenge.protectionSpace.host
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if isLoopback,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        #endif
        return (.performDefaultHandling, nil)
    }
}
