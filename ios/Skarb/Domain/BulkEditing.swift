import Foundation

/// Which transactions are ticked in selection mode.
///
/// A set of ids rather than of rows, and deliberately one that outlives the page and the filters it
/// was made under: search one merchant, tick them, search the next, tick those, then file the lot.
nonisolated struct BulkSelection: Equatable, Sendable {
    private(set) var ids: Set<UUID> = []

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    mutating func toggle(_ id: UUID) {
        if ids.remove(id) == nil { ids.insert(id) }
    }

    /// Whether every row of a day is ticked — what decides "Select day" against "Clear day".
    func containsAll(_ day: [UUID]) -> Bool {
        !day.isEmpty && day.allSatisfy(ids.contains)
    }

    /// Ticks a whole day, or clears it when it was already fully ticked.
    mutating func toggleAll(_ day: [UUID]) {
        if containsAll(day) { ids.subtract(day) } else { ids.formUnion(day) }
    }

    /// "Select all N": everything the filters match, which replaces what was ticked by hand —
    /// it is the bigger set by construction, and merging would quietly keep rows the current
    /// filters no longer show.
    mutating func replace(with all: [UUID]) { ids = Set(all) }

    mutating func clear() { ids.removeAll() }
}

/// What a selection can have done to it, and how the toast finishes "12 transactions …".
nonisolated enum BulkAction: Equatable, Sendable {
    /// Nil files the rows as uncategorized.
    case file(Category?)
    case addTag(Tag)
    case removeTag(Tag)
    case markInternal(Bool)
    case exclude(Bool)

    var patch: BulkPatch {
        switch self {
        case .file(let category): BulkPatch(categorySet: true, categoryId: category?.id)
        case .addTag(let tag): BulkPatch(addTagIds: [tag.id])
        case .removeTag(let tag): BulkPatch(removeTagIds: [tag.id])
        case .markInternal(let on): BulkPatch(isInternal: on)
        case .exclude(let on): BulkPatch(isExcluded: on)
        }
    }

    var outcome: String {
        switch self {
        case .file(let category?): "filed under \(category.label)"
        case .file(nil): "left uncategorized"
        case .addTag(let tag): "tagged #\(tag.name)"
        case .removeTag(let tag): "no longer tagged #\(tag.name)"
        case .markInternal(true): "marked internal"
        case .markInternal(false): "no longer internal"
        case .exclude(true): "excluded from stats"
        case .exclude(false): "counted again"
        }
    }

    static func summary(updated: Int, _ action: BulkAction) -> String {
        "\(updated) transaction\(updated == 1 ? "" : "s") \(action.outcome)"
    }

    /// Said when "select all" hit the server's cap rather than the end of the history.
    static func capNote(selected: Int, total: Int) -> String? {
        total > selected ? "Selected the newest \(selected) of \(total) — the rest is one more pass" : nil
    }
}
