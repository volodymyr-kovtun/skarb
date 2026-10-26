import Foundation

// Where transactions come from: bank connections, the two ways of linking one, syncing them,
// and statement files for the banks with no API at all.

@MainActor
protocol ConnectionService {
    func connections() async throws -> [Connection]
    func rename(_ id: UUID, to name: String) async throws -> Connection
    func delete(_ id: UUID) async throws
    /// Forgets the accounts deleted from this connection; the next sync brings them back.
    func restoreIgnoredAccounts(_ id: UUID) async throws -> Int
    func connectMonobank(token: String) async throws
    /// Asks Monobank to push every payment to this server as it happens. Answers with the URL
    /// that was registered.
    func registerMonobankWebhook(_ id: UUID, publicBaseURL: String) async throws -> String
}

/// Linking a bank through Enable Banking: register the owner's application, pick a bank,
/// authorize at the bank, and hand the code that comes back to the server.
@MainActor
protocol EnableBankingService {
    func createConnection(displayName: String, applicationId: String, privateKeyPEM: String) async throws -> UUID
    func banks(for connection: UUID, country: String) async throws -> [Aspsp]
    /// The bank's authorization page. `redirectURL` must be one the owner registered.
    func authorize(_ connection: UUID, bank: Aspsp, redirectURL: URL) async throws -> URL
    func complete(_ connection: UUID, code: String) async throws
}

@MainActor
protocol SyncService {
    func syncAll() async throws
    /// `full` re-fetches the whole history and refreshes the rows already there.
    func sync(_ connection: UUID, full: Bool) async throws
    func status() async throws -> SyncStatus
}

@MainActor
protocol ImportService {
    func importCSV(_ request: CSVImportRequest) async throws -> CSVImportResult
}

struct LiveConnectionService: ConnectionService {
    let http: any HTTPClient

    func connections() async throws -> [Connection] { try await http.send(.get("/api/connections")) }

    func rename(_ id: UUID, to name: String) async throws -> Connection {
        try await http.send(.patch("/api/connections/\(id.uuidString)", body: RenameBody(displayName: name)))
    }

    func delete(_ id: UUID) async throws {
        let _: NoContent = try await http.send(.delete("/api/connections/\(id.uuidString)"))
    }

    func restoreIgnoredAccounts(_ id: UUID) async throws -> Int {
        let result: Restored = try await http.send(.post(
            "/api/connections/\(id.uuidString)/ignored/restore", body: EmptyBody()))
        return result.restored
    }

    func connectMonobank(token: String) async throws {
        let _: Created = try await http.send(.post("/api/connections/monobank", body: TokenBody(token: token)))
    }

    func registerMonobankWebhook(_ id: UUID, publicBaseURL: String) async throws -> String {
        let result: Webhook = try await http.send(.post(
            "/api/connections/\(id.uuidString)/monobank/webhook",
            body: WebhookBody(publicBaseUrl: publicBaseURL)))
        return result.webhookUrl
    }
}

struct LiveEnableBankingService: EnableBankingService {
    let http: any HTTPClient

    func createConnection(displayName: String, applicationId: String, privateKeyPEM: String) async throws -> UUID {
        let created: Created = try await http.send(.post("/api/connections/enablebanking", body: EnableBankingBody(
            displayName: displayName, applicationId: applicationId, privateKeyPem: privateKeyPEM)))
        return created.id
    }

    func banks(for connection: UUID, country: String) async throws -> [Aspsp] {
        try await http.send(.get(
            "/api/connections/\(connection.uuidString)/enablebanking/aspsps",
            query: [URLQueryItem(name: "country", value: country)]))
    }

    func authorize(_ connection: UUID, bank: Aspsp, redirectURL: URL) async throws -> URL {
        let result: Authorization = try await http.send(.post(
            "/api/connections/\(connection.uuidString)/enablebanking/authorize",
            body: AuthorizeBody(
                aspspName: bank.name, aspspCountry: bank.country,
                redirectUrl: redirectURL.absoluteString, client: EnableBankingHandoff.client)))
        guard let url = URL(string: result.url) else {
            throw APIError(message: "Enable Banking sent an authorization link that isn't a link.", status: 0)
        }
        return url
    }

    func complete(_ connection: UUID, code: String) async throws {
        let _: NoContent = try await http.send(.post(
            "/api/connections/\(connection.uuidString)/enablebanking/complete", body: CodeBody(code: code)))
    }
}

struct LiveSyncService: SyncService {
    let http: any HTTPClient

    func syncAll() async throws {
        let _: NoContent = try await http.send(.post("/api/sync"))
    }

    func sync(_ connection: UUID, full: Bool) async throws {
        let _: NoContent = try await http.send(.post(
            "/api/sync/\(connection.uuidString)",
            query: full ? [URLQueryItem(name: "full", value: "true")] : []))
    }

    func status() async throws -> SyncStatus { try await http.send(.get("/api/sync/status")) }
}

struct LiveImportService: ImportService {
    let http: any HTTPClient

    func importCSV(_ request: CSVImportRequest) async throws -> CSVImportResult {
        try await http.send(.post("/api/import/csv", body: request))
    }
}

private nonisolated struct RenameBody: Encodable, Sendable { var displayName: String }
private nonisolated struct TokenBody: Encodable, Sendable { var token: String }
private nonisolated struct WebhookBody: Encodable, Sendable { var publicBaseUrl: String }
private nonisolated struct CodeBody: Encodable, Sendable { var code: String }
private nonisolated struct Restored: Decodable, Sendable { var restored: Int }
private nonisolated struct Created: Decodable, Sendable { var id: UUID }
private nonisolated struct Webhook: Decodable, Sendable { var webhookUrl: String }
private nonisolated struct Authorization: Decodable, Sendable { var url: String }

private nonisolated struct EnableBankingBody: Encodable, Sendable {
    var displayName: String
    var applicationId: String
    var privateKeyPem: String
}

private nonisolated struct AuthorizeBody: Encodable, Sendable {
    var aspspName: String
    var aspspCountry: String
    var redirectUrl: String
    var client: String
}
