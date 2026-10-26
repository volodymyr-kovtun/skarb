import Foundation

@MainActor
protocol TransactionService {
    func page(_ filter: TransactionFilter, page: Int, pageSize: Int) async throws -> Paged<Tx>
    /// Every id the same filter matches, newest first — what "select all" selects. The server
    /// caps it, and says how many there were in all.
    func ids(matching filter: TransactionFilter) async throws -> TransactionIDs
    func create(_ body: NewTransaction) async throws -> Tx
    func update(_ id: UUID, _ patch: TransactionPatch) async throws -> Tx
    func bulkUpdate(_ ids: [UUID], _ patch: BulkPatch) async throws -> BulkResult
    func delete(_ id: UUID) async throws
    /// What a withdrawal would have paid out in another currency at today's rate; nil = no rate.
    func cashEstimate(for id: UUID, in currency: String) async throws -> Decimal?
    /// What a manual category change on this transaction could become. Nil `pattern` = the guess.
    func ruleSuggestion(for id: UUID, pattern: String?) async throws -> RuleSuggestion
}

struct LiveTransactionService: TransactionService {
    let http: any HTTPClient

    func page(_ filter: TransactionFilter, page: Int, pageSize: Int) async throws -> Paged<Tx> {
        try await http.send(.get("/api/transactions", query: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ] + filter.queryItems))
    }

    func ids(matching filter: TransactionFilter) async throws -> TransactionIDs {
        try await http.send(.get("/api/transactions/ids", query: filter.queryItems))
    }

    func create(_ body: NewTransaction) async throws -> Tx {
        try await http.send(.post("/api/transactions", body: body))
    }

    func update(_ id: UUID, _ patch: TransactionPatch) async throws -> Tx {
        try await http.send(.patch("/api/transactions/\(id.uuidString)", body: patch))
    }

    func bulkUpdate(_ ids: [UUID], _ patch: BulkPatch) async throws -> BulkResult {
        try await http.send(.post("/api/transactions/bulk", body: BulkBody(ids: ids, patch: patch)))
    }

    func delete(_ id: UUID) async throws {
        let _: NoContent = try await http.send(.delete("/api/transactions/\(id.uuidString)"))
    }

    func cashEstimate(for id: UUID, in currency: String) async throws -> Decimal? {
        let estimate: CashEstimate = try await http.send(.get(
            "/api/transactions/\(id.uuidString)/cash-estimate",
            query: [URLQueryItem(name: "currency", value: currency)]))
        return estimate.amount
    }

    func ruleSuggestion(for id: UUID, pattern: String?) async throws -> RuleSuggestion {
        try await http.send(.get(
            "/api/transactions/\(id.uuidString)/rule-suggestion",
            query: pattern.map { [URLQueryItem(name: "pattern", value: $0)] } ?? []))
    }
}

/// `{ ids, ...patch }` — the selection and the edit side by side, as the endpoint binds them.
nonisolated struct BulkBody: Encodable, Sendable {
    var ids: [UUID]
    var patch: BulkPatch

    private enum CodingKeys: String, CodingKey {
        case ids, categorySet, categoryId, addTagIds, removeTagIds, isInternal, isExcluded
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ids, forKey: .ids)
        try c.encode(patch.categorySet, forKey: .categorySet)
        try c.encodeIfPresent(patch.categoryId, forKey: .categoryId)
        try c.encodeIfPresent(patch.addTagIds, forKey: .addTagIds)
        try c.encodeIfPresent(patch.removeTagIds, forKey: .removeTagIds)
        try c.encodeIfPresent(patch.isInternal, forKey: .isInternal)
        try c.encodeIfPresent(patch.isExcluded, forKey: .isExcluded)
    }
}

private nonisolated struct CashEstimate: Decodable, Sendable { var amount: Decimal? }
