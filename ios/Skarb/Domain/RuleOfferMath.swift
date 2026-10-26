import Foundation

/// What the rule offer's "also file the ones I already have" toggle would actually do.
nonisolated struct RuleOfferMath: Equatable, Sendable {
    var counts: RuleMatchCounts
    var applyPast: Bool
    var includeUntouched: Bool

    /// Guesses — uncategorized, or filed by a rule or a card code. Re-filing these needs no asking.
    var automatic: Int { counts.uncategorized + counts.automatic }
    var matched: Int { automatic + counts.untouched }
    /// What the toggle would rewrite — hand-sorted rows are held back until asked for by name.
    var changing: Int { includeUntouched ? matched : automatic }

    var scope: RuleScope { !applyPast ? .none : (includeUntouched ? .all : .automatic) }

    /// Says which of the matches are guesses and which are decisions, so neither is a surprise.
    var breakdown: String {
        var parts: [String] = []
        if counts.uncategorized > 0 { parts.append("\(counts.uncategorized) uncategorized") }
        if counts.automatic > 0 { parts.append("\(counts.automatic) filed automatically") }
        let lead = parts.isEmpty ? "" : parts.joined(separator: ", ") + "."
        guard counts.untouched > 0 else { return lead }
        let them = counts.untouched == 1 ? "it is" : "they are"
        let tail = "\(counts.untouched) you sorted by hand "
            + (includeUntouched ? "will be re-filed too." : "stay as \(them).")
        return lead.isEmpty ? tail : lead + " " + tail
    }

    static func savedMessage(applied: Int) -> String {
        applied > 0
            ? "Rule saved · \(applied) transaction\(applied == 1 ? "" : "s") re-filed"
            : "Rule saved"
    }
}
