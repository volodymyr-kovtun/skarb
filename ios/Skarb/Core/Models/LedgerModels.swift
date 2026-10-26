import Foundation

// The API's contracts, mirrored from `frontend/src/shared/api.ts` so the two clients read the
// same server the same way. ASP.NET serializes camelCase, which is what these names decode from.
// They are plain, `Sendable` values with no behaviour beyond naming what they hold; anything that
// decides something lives in Domain, where it can be tested.

nonisolated enum CategoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense, income, investment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "Spending"
        case .income: "Income"
        case .investment: "Investments"
        }
    }

    var blurb: String {
        switch self {
        case .expense: "Day-to-day money out — counted as spending."
        case .income: "Money coming in — salary, freelance, cashback."
        case .investment: "Contributions to brokers or savings — tracked as \"Invested\", never as spending."
        }
    }
}

nonisolated struct Category: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var emoji: String
    var color: String
    var kind: CategoryKind

    /// "🍔 Food", the way a category is named in a picker or a sentence.
    var label: String { "\(emoji) \(name)" }
}

nonisolated struct CategoryWithCount: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var emoji: String
    var color: String
    var kind: CategoryKind
    var transactionCount: Int

    var category: Category { Category(id: id, name: name, emoji: emoji, color: color, kind: kind) }
}

nonisolated struct Tag: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var color: String
}

nonisolated enum ProviderName {
    static let manual = "manual"
    static let monobank = "monobank"
    static let enableBanking = "enablebanking"
}

nonisolated struct Account: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var bank: String
    var provider: String
    var currency: String
    var balance: Decimal
    var iban: String?
    var maskedPan: String?
    var color: String
    var isArchived: Bool
    var isExcluded: Bool
    var connectionId: UUID?
    /// Alert when the balance drops below this (account currency); nil = alerts off.
    var lowBalanceThreshold: Decimal?
    /// Telegram chat this account alerts; nil = the default chat from Settings.
    var lowBalanceChatId: String?
    /// The cash held in this currency, where withdrawals land. There is at most one per currency.
    var isCash: Bool

    var isManual: Bool { provider == ProviderName.manual }

    /// Institution an account is grouped under. Manual accounts have no bank of their own, and
    /// cash wallets always gather under one heading — including one that was a plain manual
    /// account first and still carries whatever it was filed under then.
    var bankLabel: String { isCash ? "Cash" : (bank.isEmpty ? "Manual" : bank) }

    /// "PKO BP · Savings", for pickers where accounts from several banks sit in one list.
    var label: String { bank.isEmpty ? name : "\(bank) · \(name)" }

    /// The last few digits of whatever identifies the account, for a subtitle.
    var tail: String? {
        if let maskedPan, !maskedPan.isEmpty { return String(maskedPan.suffix(8)) }
        if let iban, iban.count > 6 { return "…" + String(iban.suffix(6)) }
        return nil
    }
}

nonisolated struct Meta: Codable, Sendable {
    var accounts: [Account]
    var categories: [Category]
    var tags: [Tag]
}

nonisolated struct Paged<T: Codable & Sendable>: Codable, Sendable {
    var items: [T]
    var total: Int
    var page: Int
    var pageSize: Int
}

// MARK: - Writing

nonisolated struct NewAccount: Encodable, Sendable, Equatable {
    /// Nil for a cash wallet: the server names and files one by its currency.
    var name: String?
    var bank: String?
    var currency: String
    var balance: Decimal
    var color: String?
    var isCash = false
}

nonisolated struct AccountPatch: Encodable, Sendable, Equatable {
    var name: String?
    var color: String?
    var isArchived: Bool?
    var isExcluded: Bool?
    /// Set true to apply the two lowBalance fields; a nil threshold turns the alert off.
    var lowBalanceSet = false
    var lowBalanceThreshold: Decimal?
    var lowBalanceChatId: String?
    var isCash: Bool?
}

nonisolated struct CategoryBody: Encodable, Sendable, Equatable {
    var name: String
    var emoji: String
    var color: String
    var kind: CategoryKind
}
