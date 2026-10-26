import Foundation

/// The two reads every screen leans on: the shared lists, and the overview's figures.
@MainActor
protocol LedgerService {
    func meta() async throws -> Meta
    func dashboard(currency: String?, period: PeriodKey) async throws -> Dashboard
}

struct LiveLedgerService: LedgerService {
    let http: any HTTPClient

    func meta() async throws -> Meta { try await http.send(.get("/api/meta")) }

    func dashboard(currency: String?, period: PeriodKey) async throws -> Dashboard {
        var query = [URLQueryItem(name: "period", value: period.rawValue)]
        if let currency, !currency.isEmpty {
            query.append(URLQueryItem(name: "currency", value: currency))
        }
        return try await http.send(.get("/api/dashboard", query: query))
    }
}
