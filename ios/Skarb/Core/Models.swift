import Foundation

// The API's contracts, mirrored from `frontend/src/shared/api.ts` so the two clients read the
// same server the same way. ASP.NET serializes camelCase, which is what these names decode from.

nonisolated enum CategoryKind: String, Codable, CaseIterable, Sendable {
    case expense, income, investment

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

    /// Institution an account is grouped under. Manual accounts have no bank of their own.
    var bankLabel: String { bank.isEmpty ? "Manual" : bank }
    var label: String { bank.isEmpty ? name : "\(bank) · \(name)" }
    /// The last few digits of whatever identifies the account, for a subtitle.
    var tail: String? {
        if let maskedPan, !maskedPan.isEmpty { return String(maskedPan.suffix(8)) }
        if let iban, iban.count > 6 { return "…" + String(iban.suffix(6)) }
        return nil
    }
}

nonisolated struct Tx: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var accountId: UUID
    var accountName: String
    var accountColor: String
    var bank: String
    var amount: Decimal
    var currency: String
    var description: String
    var counterParty: String?
    var mcc: Int?
    var category: Category?
    var tags: [Tag]
    var occurredAt: Date
    var source: String
    var note: String?
    var isExcluded: Bool
    var isInternal: Bool
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

nonisolated struct Dashboard: Codable, Sendable {
    struct AccountBalance: Codable, Identifiable, Sendable {
        var account: Account
        var balanceConverted: Decimal
        var id: UUID { account.id }
    }

    /// The window every figure is counted over, and the one it is measured against.
    /// All four dates are inclusive, so they can be printed exactly as they were counted.
    struct Window: Codable, Sendable {
        var key: PeriodKey
        var start: String
        var end: String
        var previousStart: String
        var previousEnd: String
    }

    struct Totals: Codable, Sendable {
        var income: Decimal
        var expense: Decimal
        var invested: Decimal
        var net: Decimal
    }

    struct Previous: Codable, Sendable {
        var income: Decimal
        var expense: Decimal
        var invested: Decimal
    }

    struct CategorySlice: Codable, Sendable {
        var categoryId: UUID?
        var name: String
        var emoji: String
        var color: String
        var amount: Decimal
    }

    struct AccountSlice: Codable, Sendable {
        var accountId: UUID
        var name: String
        var bank: String
        var color: String
        var amount: Decimal
    }

    struct TagSlice: Codable, Sendable {
        var tagId: UUID
        var name: String
        var color: String
        var amount: Decimal
    }

    struct Month: Codable, Sendable {
        var month: String
        var income: Decimal
        var expense: Decimal
        var invested: Decimal
    }

    /// Currency every converted number here is reported in.
    var currency: String
    var baseCurrency: String
    var availableCurrencies: [String]
    var netWorth: Decimal
    var accounts: [AccountBalance]
    var period: Window
    var totals: Totals
    var previous: Previous
    /// Net contributions to investment categories over all time — deliberately outside the window.
    var allTimeInvested: Decimal
    var spendingByCategory: [CategorySlice]
    var spendingByAccount: [AccountSlice]
    var spendingByTag: [TagSlice]
    /// The window's spending carrying no tag at all.
    var untaggedSpending: Decimal
    /// Transactions in the window wearing more than one tag — why tag slices can overlap.
    var multiTagCount: Int
    /// Per-month context around the window rather than the window itself.
    var cashflow: [Month]
    var recent: [Tx]
}

nonisolated struct Connection: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var provider: String
    var displayName: String
    var status: String
    var lastSyncedAt: Date?
    var lastError: String?
    var accountCount: Int
    var consentValidUntil: Date?
    /// Accounts deleted from this connection, which sync no longer recreates.
    var ignoredAccountCount: Int
}

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
nonisolated struct RuleMatchCounts: Codable, Sendable {
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
nonisolated struct RuleRevert: Codable, Sendable {
    var transactionId: UUID
    var previousCategoryId: UUID?
    var previousSource: String?
}

nonisolated struct RuleApplied: Codable, Sendable {
    let id: UUID
    var applied: Int
    var reverts: [RuleRevert]
}

nonisolated struct SyncStatus: Codable, Sendable {
    struct LogEntry: Codable, Sendable, Identifiable {
        var at: Date
        var provider: String
        var message: String
        var success: Bool
        var newTransactions: Int
        var id: String { "\(at.timeIntervalSince1970)-\(provider)-\(message)" }
    }

    var running: [String]
    var logs: [LogEntry]
}

nonisolated struct TelegramSettings: Codable, Sendable {
    var hasToken: Bool
    var botUsername: String?
}

nonisolated struct TelegramChat: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
}

nonisolated struct Session: Codable, Sendable {
    var authenticated: Bool
    var email: String?
    var setupRequired: Bool
}

nonisolated struct RecoveryCodes: Codable, Sendable {
    var recoveryCodes: [String]
}
