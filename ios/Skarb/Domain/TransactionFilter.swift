import Foundation

/// Everything the transactions list can be narrowed by, in one value the view can diff on.
///
/// The server binds these same parameters both for a page of rows and for "select everything
/// that matches", so the two can never disagree about what a filter means — which is why this is
/// the one place their query string is written.
nonisolated struct TransactionFilter: Hashable, Sendable {
    enum Special: String, Hashable, Sendable, CaseIterable {
        case uncategorized, internalOnly, investmentsOnly

        var label: String {
            switch self {
            case .uncategorized: "Uncategorized"
            case .internalOnly: "Internal"
            case .investmentsOnly: "Investments"
            }
        }

        /// The longer form a menu has room for, matching the web's select.
        var menuLabel: String {
            switch self {
            case .uncategorized: "· Uncategorized"
            case .internalOnly: "🔁 Internal transfers"
            case .investmentsOnly: "📈 Investments"
            }
        }
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

    /// Hiding transfers while asking only for transfers would always come back empty, so the
    /// "internal" filter wins and the toggle is offered as off.
    var canHideInternal: Bool { special != .internalOnly }

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
        if hideInternal, canHideInternal {
            items.append(.init(name: "hideInternal", value: "true"))
        }
        return items
    }

    /// A stable string for `.task(id:)` — two filters that ask the same question share it.
    var key: String {
        queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }
}
