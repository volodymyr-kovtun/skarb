import Foundation

// How money gets labeled: categories, the tags beside them, and the keyword rules that file
// transactions into both. Three protocols rather than one, so a screen that only renames a tag
// depends on nothing that can delete a rule.

@MainActor
protocol CategoryService {
    func categories() async throws -> [CategoryWithCount]
    func create(_ body: CategoryBody) async throws -> Category
    func update(_ id: UUID, _ body: CategoryBody) async throws -> Category
    func delete(_ id: UUID) async throws
}

@MainActor
protocol TagService {
    func create(name: String, color: String?) async throws -> Tag
    func update(_ id: UUID, name: String?, color: String?) async throws -> Tag
    func delete(_ id: UUID) async throws
}

@MainActor
protocol RuleService {
    func rules() async throws -> [Rule]
    /// No priority on purpose: the server sorts a hand-written rule ahead of the seeded ones,
    /// which is the only way it can beat a broad default like "supermarket" or "fee".
    func create(pattern: String, categoryId: UUID, applyTo: RuleScope) async throws -> RuleApplied
    func update(_ id: UUID, categoryId: UUID, pattern: String?, applyTo: RuleScope) async throws -> RuleApplied
    func delete(_ id: UUID) async throws
    /// Runs every rule over transactions that carry no category yet. It only fills blanks.
    func applyToUncategorized() async throws -> RulesApplyResult
    /// Puts back what a rule apply or a bulk edit re-filed, from the list it handed back.
    func revert(_ entries: [RuleRevert]) async throws
}

struct LiveCategoryService: CategoryService {
    let http: any HTTPClient

    func categories() async throws -> [CategoryWithCount] { try await http.send(.get("/api/categories")) }

    func create(_ body: CategoryBody) async throws -> Category {
        try await http.send(.post("/api/categories", body: body))
    }

    func update(_ id: UUID, _ body: CategoryBody) async throws -> Category {
        try await http.send(.patch("/api/categories/\(id.uuidString)", body: body))
    }

    func delete(_ id: UUID) async throws {
        let _: NoContent = try await http.send(.delete("/api/categories/\(id.uuidString)"))
    }
}

struct LiveTagService: TagService {
    let http: any HTTPClient

    func create(name: String, color: String?) async throws -> Tag {
        try await http.send(.post("/api/tags", body: TagBody(name: name, color: color)))
    }

    func update(_ id: UUID, name: String?, color: String?) async throws -> Tag {
        try await http.send(.patch("/api/tags/\(id.uuidString)", body: TagBody(name: name, color: color)))
    }

    func delete(_ id: UUID) async throws {
        let _: NoContent = try await http.send(.delete("/api/tags/\(id.uuidString)"))
    }
}

struct LiveRuleService: RuleService {
    let http: any HTTPClient

    func rules() async throws -> [Rule] { try await http.send(.get("/api/rules")) }

    func create(pattern: String, categoryId: UUID, applyTo: RuleScope) async throws -> RuleApplied {
        try await http.send(.post("/api/rules", body: NewRule(
            pattern: pattern, categoryId: categoryId, applyTo: applyTo)))
    }

    func update(_ id: UUID, categoryId: UUID, pattern: String?, applyTo: RuleScope) async throws -> RuleApplied {
        try await http.send(.patch("/api/rules/\(id.uuidString)", body: RulePatch(
            categoryId: categoryId, pattern: pattern, applyTo: applyTo)))
    }

    func delete(_ id: UUID) async throws {
        let _: NoContent = try await http.send(.delete("/api/rules/\(id.uuidString)"))
    }

    func applyToUncategorized() async throws -> RulesApplyResult {
        try await http.send(.post("/api/rules/apply", body: EmptyBody()))
    }

    func revert(_ entries: [RuleRevert]) async throws {
        let _: NoContent = try await http.send(.post("/api/rules/revert", body: RevertBody(entries: entries)))
    }
}

private nonisolated struct TagBody: Encodable, Sendable {
    var name: String?
    var color: String?
}

private nonisolated struct NewRule: Encodable, Sendable {
    var pattern: String
    var categoryId: UUID
    var applyTo: RuleScope
}

private nonisolated struct RulePatch: Encodable, Sendable {
    var categoryId: UUID
    var pattern: String?
    var applyTo: RuleScope
}

private nonisolated struct RevertBody: Encodable, Sendable { var entries: [RuleRevert] }
