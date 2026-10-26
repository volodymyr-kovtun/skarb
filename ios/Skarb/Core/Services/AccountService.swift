import Foundation

@MainActor
protocol AccountService {
    func create(_ body: NewAccount) async throws -> Account
    func update(_ id: UUID, _ patch: AccountPatch) async throws -> Account
    func delete(_ id: UUID) async throws
}

struct LiveAccountService: AccountService {
    let http: any HTTPClient

    func create(_ body: NewAccount) async throws -> Account {
        try await http.send(.post("/api/accounts", body: body))
    }

    func update(_ id: UUID, _ patch: AccountPatch) async throws -> Account {
        try await http.send(.patch("/api/accounts/\(id.uuidString)", body: patch))
    }

    func delete(_ id: UUID) async throws {
        let _: NoContent = try await http.send(.delete("/api/accounts/\(id.uuidString)"))
    }
}
