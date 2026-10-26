import Foundation

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
    /// Per-month context around the window rather than the window itself: it always runs to the
    /// current month, so the net-worth line can be walked back from today's balance.
    var cashflow: [Month]
    var recent: [Tx]
}
