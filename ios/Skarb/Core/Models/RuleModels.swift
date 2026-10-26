import Foundation

nonisolated struct Rule: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var pattern: String
    var priority: Int
    var category: Category
}

/// How far back a rule reaches over transactions that already exist.
nonisolated enum RuleScope: String, Codable, Sendable {
    case none, automatic, all
}

/// Matching transactions a rule would change, split by how much of a decision their current
/// category was. `untouched` is the ones filed by hand — only rewritten when asked for by name.
nonisolated struct RuleMatchCounts: Codable, Hashable, Sendable {
    var uncategorized: Int
    var automatic: Int
    var untouched: Int
}

nonisolated struct RuleSuggestion: Codable, Sendable {
    struct ExistingRule: Codable, Sendable {
        let id: UUID
        var pattern: String
        var category: Category
    }

    /// Nil means there is nothing worth offering here — don't show the sheet.
    var pattern: String?
    var alternatives: [String]
    /// Set when a rule already claims this keyword: repoint it rather than adding a second.
    var existingRule: ExistingRule?
    var matches: RuleMatchCounts
    var sample: [Tx]
}

/// One rewritten transaction and what it was filed as before — everything undo needs.
nonisolated struct RuleRevert: Codable, Hashable, Sendable {
    var transactionId: UUID
    var previousCategoryId: UUID?
    var previousSource: String?
}

nonisolated struct RuleApplied: Codable, Sendable {
    let id: UUID
    var applied: Int
    var reverts: [RuleRevert]
}

/// What "apply to uncategorized" got through: it only ever fills blanks.
nonisolated struct RulesApplyResult: Codable, Sendable {
    var scanned: Int
    var categorized: Int
}
