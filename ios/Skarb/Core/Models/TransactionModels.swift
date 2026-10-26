import Foundation

nonisolated enum TransactionSource {
    static let manual = "manual"
    /// The wallet side of a cash withdrawal — written by Skarb, never typed or synced.
    static let cash = "cash"
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
    /// On a withdrawal that was moved to a cash wallet: what the wallet received. The wallet's own
    /// row carries `source == "cash"` instead, and has no `cash` of its own.
    var cash: CashLeg?
    /// What the operation was worth in another currency, when the bank said: a card payment
    /// abroad, or the far side of a currency exchange between two wallets.
    var originalAmount: Decimal?
    var originalCurrency: String?

    var isManual: Bool { source == TransactionSource.manual }
    var isWalletSide: Bool { source == TransactionSource.cash }
}

/// What a cash withdrawal put in the wallet. `corrected` means the owner said so — otherwise it is
/// simply the bank's amount, and follows it if a hold settles at a different figure.
nonisolated struct CashLeg: Codable, Hashable, Sendable {
    var amount: Decimal
    var currency: String
    var corrected: Bool
}

nonisolated struct TransactionIDs: Codable, Sendable {
    var ids: [UUID]
    var total: Int
}

/// A bulk edit hands back what each re-filed row was before, so the toast can offer an undo.
nonisolated struct BulkResult: Codable, Sendable {
    var updated: Int
    var reverts: [RuleRevert]
}

// MARK: - Writing

nonisolated struct NewTransaction: Encodable, Sendable, Equatable {
    var accountId: UUID
    var amount: Decimal
    var description: String
    var categoryId: UUID?
    var tagIds: [UUID]
    var occurredAt: Date
    var note: String?
}

/// A partial update. Only the fields that are set travel; `categorySet` and `cashSet` are what
/// tell the server that a nil beside them means "clear it" rather than "leave it alone".
nonisolated struct TransactionPatch: Encodable, Sendable, Equatable {
    var description: String?
    var amount: Decimal?
    var occurredAt: Date?
    var note: String?
    var isExcluded: Bool?
    var isInternal: Bool?
    var categorySet = false
    var categoryId: UUID?
    var tagIds: [UUID]?
    /// Set true to apply the two cash fields. A nil amount in another currency asks the server to
    /// convert at today's rate and freeze it; a nil amount in the bank's currency means "exactly
    /// what left the account".
    var cashSet = false
    var cashCurrency: String?
    var cashAmount: Decimal?
}

/// One edit over a selection. Fields left nil are left alone.
nonisolated struct BulkPatch: Encodable, Sendable, Equatable {
    var categorySet = false
    var categoryId: UUID?
    var addTagIds: [UUID]?
    var removeTagIds: [UUID]?
    var isInternal: Bool?
    var isExcluded: Bool?
}
