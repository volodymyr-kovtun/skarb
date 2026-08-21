import Foundation

/// No session, or it expired. Kept separate so the app can fall back to the sign-in screen
/// instead of showing a broken page — the same split the web client makes.
nonisolated struct UnauthorizedError: LocalizedError {
    var message = "Your session has ended. Please sign in again."
    var errorDescription: String? { message }
}

/// Anything the server refused with a message of its own — a bad token, an expired consent,
/// a rate limit. Its text is meant to be shown.
nonisolated struct APIError: LocalizedError {
    var message: String
    var status: Int
    var errorDescription: String? { message }
}

/// The one place that talks to a Skarb server.
///
/// Authentication is the same HttpOnly `skarb.session` cookie the web client uses, so this
/// keeps its own cookie jar on disk and lets `URLSession` carry it. Nothing here stores a
/// password or a token; signing out is the server clearing the cookie.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let cookies = HTTPCookieStorage.shared

    /// Where the ledger lives. Changing it drops the cookies of the server you left.
    var baseURL: URL {
        get { ServerSettings.baseURL }
        set { ServerSettings.baseURL = newValue }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        session = URLSession(
            configuration: config, delegate: LocalhostTrustDelegate(), delegateQueue: nil)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Not an ISO-8601 date: \(text)")
            }
            return date
        }

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.string(date))
        }
    }

    /// Forgets the session cookie for the current server. Used when switching servers, and as
    /// a belt-and-braces companion to `POST /api/auth/logout`.
    func clearCookies() {
        for cookie in cookies.cookies ?? [] where cookie.name.hasPrefix("skarb.") {
            cookies.deleteCookie(cookie)
        }
    }

    // MARK: - Transport

    private func request(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        else { throw APIError(message: "That server address isn't valid.", status: 0) }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw APIError(message: "That server address isn't valid.", status: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        request.httpShouldHandleCookies = true
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError(message: Self.friendly(error), status: 0)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "The server sent something unexpected.", status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            // The API answers failures as `{ "error": "..." }`; that text is written for a
            // person, so it is preferred over the status line whenever it is there.
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized
            if http.statusCode == 401 { throw UnauthorizedError(message: message) }
            throw APIError(message: message, status: http.statusCode)
        }
        return data
    }

    @discardableResult
    private func call<T: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Encodable? = nil
    ) async throws -> T {
        let payload = try body.map { try encoder.encode(AnyEncodable($0)) }
        let data = try await send(try request(method, path, query: query, body: payload))
        if T.self == Empty.self { return Empty() as! T }
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw APIError(message: Self.explain(error, path: path), status: 0)
        } catch {
            throw APIError(
                message: "The server's answer didn't look like Skarb. Check the address.",
                status: 0)
        }
    }

    /// Turns a `DecodingError` into something worth reading.
    ///
    /// The overwhelmingly likely cause of one is version skew — the app talking to a Skarb
    /// older than itself, which simply doesn't send a field the app now needs. "Didn't look
    /// like Skarb" sends you off checking the address, which is the one thing that isn't
    /// wrong. So name the field that was missing, and name the fix.
    private static func explain(_ error: DecodingError, path: String) -> String {
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

    private func callVoid(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Encodable? = nil
    ) async throws {
        let payload = try body.map { try encoder.encode(AnyEncodable($0)) }
        _ = try await send(try request(method, path, query: query, body: payload))
    }

    private static func friendly(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: "You're offline."
        case .timedOut: "The server took too long to answer."
        case .cannotFindHost, .cannotConnectToHost: "Couldn't reach that server."
        case .secureConnectionFailed, .serverCertificateUntrusted:
            "The server's certificate wasn't trusted."
        default: error.localizedDescription
        }
    }

    struct Empty: Codable, Sendable {}
}

// MARK: - Endpoints

extension APIClient {
    // --- auth ---

    func session() async throws -> Session { try await call("GET", "/api/auth/session") }

    func login(email: String, password: String, code: String?, recoveryCode: String?) async throws {
        try await callVoid("POST", "/api/auth/login", body: LoginBody(
            email: email, password: password, code: code, recoveryCode: recoveryCode))
    }

    func logout() async throws {
        try await callVoid("POST", "/api/auth/logout")
        clearCookies()
    }

    func changePassword(current: String, new: String) async throws {
        try await callVoid(
            "POST", "/api/auth/password",
            body: ChangePasswordBody(currentPassword: current, newPassword: new))
    }

    @discardableResult
    func newRecoveryCodes(currentPassword: String) async throws -> RecoveryCodes {
        try await call(
            "POST", "/api/auth/recovery-codes", body: CurrentPasswordBody(currentPassword: currentPassword))
    }

    func recoveryCodesLeft() async throws -> Int {
        let result: [String: Int] = try await call("GET", "/api/auth/recovery-codes/remaining")
        return result["remaining"] ?? 0
    }

    // --- reading the ledger ---

    func meta() async throws -> Meta { try await call("GET", "/api/meta") }

    func dashboard(currency: String?, period: PeriodKey) async throws -> Dashboard {
        var query = [URLQueryItem(name: "period", value: period.rawValue)]
        if let currency, !currency.isEmpty {
            query.append(URLQueryItem(name: "currency", value: currency))
        }
        return try await call("GET", "/api/dashboard", query: query)
    }

    func transactions(_ filter: TransactionFilter, page: Int, pageSize: Int = 50) async throws -> Paged<Tx> {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ]
        query.append(contentsOf: filter.queryItems)
        return try await call("GET", "/api/transactions", query: query)
    }

    @discardableResult
    func createTransaction(_ body: NewTransaction) async throws -> Tx {
        try await call("POST", "/api/transactions", body: body)
    }

    @discardableResult
    func updateTransaction(_ id: UUID, _ body: TransactionPatch) async throws -> Tx {
        try await call("PATCH", "/api/transactions/\(id.uuidString)", body: body)
    }

    func deleteTransaction(_ id: UUID) async throws {
        try await callVoid("DELETE", "/api/transactions/\(id.uuidString)")
    }

    // --- accounts ---

    @discardableResult
    func createAccount(_ body: NewAccount) async throws -> Account {
        try await call("POST", "/api/accounts", body: body)
    }

    @discardableResult
    func updateAccount(_ id: UUID, _ body: AccountPatch) async throws -> Account {
        try await call("PATCH", "/api/accounts/\(id.uuidString)", body: body)
    }

    func deleteAccount(_ id: UUID) async throws {
        try await callVoid("DELETE", "/api/accounts/\(id.uuidString)")
    }

    // --- categories, tags, rules ---

    func categories() async throws -> [CategoryWithCount] { try await call("GET", "/api/categories") }

    @discardableResult
    func createCategory(_ body: CategoryBody) async throws -> Category {
        try await call("POST", "/api/categories", body: body)
    }

    @discardableResult
    func updateCategory(_ id: UUID, _ body: CategoryBody) async throws -> Category {
        try await call("PATCH", "/api/categories/\(id.uuidString)", body: body)
    }

    func deleteCategory(_ id: UUID) async throws {
        try await callVoid("DELETE", "/api/categories/\(id.uuidString)")
    }

    @discardableResult
    func createTag(name: String, color: String?) async throws -> Tag {
        try await call("POST", "/api/tags", body: TagBody(name: name, color: color))
    }

    @discardableResult
    func updateTag(_ id: UUID, name: String?, color: String?) async throws -> Tag {
        try await call("PATCH", "/api/tags/\(id.uuidString)", body: TagBody(name: name, color: color))
    }

    func deleteTag(_ id: UUID) async throws {
        try await callVoid("DELETE", "/api/tags/\(id.uuidString)")
    }

    func rules() async throws -> [Rule] { try await call("GET", "/api/rules") }

    @discardableResult
    func createRule(pattern: String, categoryId: UUID, applyTo: RuleScope) async throws -> RuleApplied {
        try await call("POST", "/api/rules", body: NewRule(
            pattern: pattern, categoryId: categoryId, priority: nil, applyTo: applyTo))
    }

    @discardableResult
    func updateRule(_ id: UUID, categoryId: UUID, pattern: String?, applyTo: RuleScope) async throws -> RuleApplied {
        try await call("PATCH", "/api/rules/\(id.uuidString)", body: RulePatch(
            categoryId: categoryId, pattern: pattern, applyTo: applyTo))
    }

    /// Runs every rule over transactions that carry no category yet. It only fills blanks.
    func applyRules() async throws -> (scanned: Int, categorized: Int) {
        let result: [String: Int] = try await call("POST", "/api/rules/apply", body: Empty())
        return (result["scanned"] ?? 0, result["categorized"] ?? 0)
    }

    func deleteRule(_ id: UUID) async throws {
        try await callVoid("DELETE", "/api/rules/\(id.uuidString)")
    }

    func revertRules(_ entries: [RuleRevert]) async throws {
        try await callVoid("POST", "/api/rules/revert", body: RevertBody(entries: entries))
    }

    /// What a manual category change on this transaction could become. Omit `pattern` for the guess.
    func ruleSuggestion(for txId: UUID, pattern: String? = nil) async throws -> RuleSuggestion {
        try await call(
            "GET", "/api/transactions/\(txId.uuidString)/rule-suggestion",
            query: pattern.map { [URLQueryItem(name: "pattern", value: $0)] } ?? [])
    }

    // --- connections and sync ---

    func connections() async throws -> [Connection] { try await call("GET", "/api/connections") }

    @discardableResult
    func renameConnection(_ id: UUID, to name: String) async throws -> Connection {
        try await call("PATCH", "/api/connections/\(id.uuidString)", body: RenameBody(displayName: name))
    }

    func deleteConnection(_ id: UUID) async throws {
        try await callVoid("DELETE", "/api/connections/\(id.uuidString)")
    }

    @discardableResult
    func restoreIgnoredAccounts(_ id: UUID) async throws -> Int {
        let result: [String: Int] = try await call(
            "POST", "/api/connections/\(id.uuidString)/ignored/restore", body: Empty())
        return result["restored"] ?? 0
    }

    func connectMonobank(token: String) async throws {
        let _: [String: UUID] = try await call(
            "POST", "/api/connections/monobank", body: MonobankBody(token: token))
    }

    func syncAll() async throws { try await callVoid("POST", "/api/sync") }

    func syncOne(_ id: UUID, full: Bool = false) async throws {
        try await callVoid(
            "POST", "/api/sync/\(id.uuidString)",
            query: full ? [URLQueryItem(name: "full", value: "true")] : [])
    }

    func syncStatus() async throws -> SyncStatus { try await call("GET", "/api/sync/status") }

    // --- notifications ---

    func telegramSettings() async throws -> TelegramSettings {
        try await call("GET", "/api/notifications/telegram")
    }

    @discardableResult
    func saveTelegramSettings(botToken: String?) async throws -> TelegramSettings {
        try await call("PATCH", "/api/notifications/telegram", body: TelegramBody(botToken: botToken))
    }

    func telegramChats() async throws -> [TelegramChat] {
        try await call("GET", "/api/notifications/telegram/chats")
    }

    @discardableResult
    func telegramTest(chatId: String) async throws -> String {
        let result: [String: String] = try await call(
            "POST", "/api/notifications/telegram/test", body: ChatBody(chatId: chatId))
        return result["sentTo"] ?? chatId
    }
}

// MARK: - Request bodies

private nonisolated struct LoginBody: Encodable {
    var email: String
    var password: String
    var code: String?
    var recoveryCode: String?
}

private nonisolated struct ChangePasswordBody: Encodable {
    var currentPassword: String
    var newPassword: String
}

private nonisolated struct CurrentPasswordBody: Encodable { var currentPassword: String }
private nonisolated struct MonobankBody: Encodable { var token: String }
private nonisolated struct RenameBody: Encodable { var displayName: String }
private nonisolated struct TelegramBody: Encodable { var botToken: String? }
private nonisolated struct ChatBody: Encodable { var chatId: String }
private nonisolated struct RevertBody: Encodable { var entries: [RuleRevert] }
private nonisolated struct TagBody: Encodable {
    var name: String?
    var color: String?
}

private nonisolated struct NewRule: Encodable {
    var pattern: String
    var categoryId: UUID
    var priority: Int?
    var applyTo: RuleScope
}

private nonisolated struct RulePatch: Encodable {
    var categoryId: UUID
    var pattern: String?
    var applyTo: RuleScope
}

nonisolated struct NewTransaction: Encodable {
    var accountId: UUID
    var amount: Decimal
    var description: String
    var categoryId: UUID?
    var tagIds: [UUID]
    var occurredAt: Date
    var note: String?
}

/// A partial update. Only the fields that are set travel, and `categorySet` is what tells the
/// server that a nil `categoryId` means "clear it" rather than "leave it alone".
nonisolated struct TransactionPatch: Encodable {
    var description: String?
    var amount: Decimal?
    var occurredAt: Date?
    var note: String?
    var isExcluded: Bool?
    var isInternal: Bool?
    var categorySet: Bool = false
    var categoryId: UUID?
    var tagIds: [UUID]?
}

nonisolated struct NewAccount: Encodable {
    var name: String
    var bank: String
    var currency: String
    var balance: Decimal
    var color: String?
}

nonisolated struct AccountPatch: Encodable {
    var name: String?
    var color: String?
    var isArchived: Bool?
    var isExcluded: Bool?
    /// Set true to apply the two lowBalance fields; a nil threshold turns the alert off.
    var lowBalanceSet: Bool = false
    var lowBalanceThreshold: Decimal?
    var lowBalanceChatId: String?
}

nonisolated struct CategoryBody: Encodable {
    var name: String
    var emoji: String
    var color: String
    var kind: CategoryKind
}

/// Everything the transactions list can be narrowed by, in one value the view can diff on.
nonisolated struct TransactionFilter: Hashable, Sendable {
    enum Special: String, Hashable, Sendable {
        case uncategorized, internalOnly, investmentsOnly
    }

    var search = ""
    var accountId: UUID?
    var categoryId: UUID?
    var special: Special?
    var tagIds: [UUID] = []
    var hideInternal = false

    var isEmpty: Bool {
        search.isEmpty && accountId == nil && categoryId == nil && special == nil
            && tagIds.isEmpty && !hideInternal
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !search.isEmpty { items.append(.init(name: "search", value: search)) }
        if let accountId { items.append(.init(name: "accountId", value: accountId.uuidString)) }
        if let categoryId { items.append(.init(name: "categoryId", value: categoryId.uuidString)) }
        // Repeated values are how the API reads a set of tags.
        for tag in tagIds { items.append(.init(name: "tagIds", value: tag.uuidString)) }
        switch special {
        case .uncategorized: items.append(.init(name: "uncategorized", value: "true"))
        case .internalOnly: items.append(.init(name: "internalOnly", value: "true"))
        case .investmentsOnly: items.append(.init(name: "investmentsOnly", value: "true"))
        case nil: break
        }
        // Asking for internal transfers and hiding them at once would only ever return
        // nothing, so the "internal" filter wins.
        if hideInternal, special != .internalOnly {
            items.append(.init(name: "hideInternal", value: "true"))
        }
        return items
    }
}

// MARK: - Plumbing

/// Lets one generic `call` take any `Encodable` body without making the whole client generic.
private nonisolated struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encode = { try wrapped.encode(to: $0) }
    }

    func encode(to encoder: Encoder) throws { try encode(encoder) }
}

/// ASP.NET writes UTC timestamps with a varying number of fractional digits, and occasionally
/// without an offset at all. One lenient parser saves every model from caring.
nonisolated enum ISO8601 {
    private nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let naive: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let naiveSeconds: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func parse(_ text: String) -> Date? {
        withFraction.date(from: text)
            ?? plain.date(from: text)
            // No offset means the server meant UTC — it stores nothing else.
            ?? naive.date(from: text)
            ?? naiveSeconds.date(from: text)
    }

    static func string(_ date: Date) -> String { plain.string(from: date) }
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
