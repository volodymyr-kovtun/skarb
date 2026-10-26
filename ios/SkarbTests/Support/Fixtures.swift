import Foundation
@testable import Skarb

// Synthetic data only — never real IBANs, tokens or statements, even in tests.

extension UUID {
    /// A readable, stable id: `UUID.n(7)` is `00000000-0000-0000-0000-000000000007`.
    static func n(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", number))!
    }
}

extension Skarb.Category {
    static func make(_ name: String, kind: CategoryKind = .expense, id: UUID = UUID()) -> Skarb.Category {
        Skarb.Category(id: id, name: name, emoji: "🏷️", color: "#426F50", kind: kind)
    }
}

extension Skarb.Tag {
    static func make(_ name: String, id: UUID = UUID()) -> Skarb.Tag {
        Skarb.Tag(id: id, name: name, color: "#9F4B25")
    }
}

extension Account {
    static func make(
        _ name: String, bank: String = "Test Bank", provider: String = ProviderName.manual,
        currency: String = "PLN", balance: Decimal = 0, isCash: Bool = false, isArchived: Bool = false,
        connectionId: UUID? = nil, id: UUID = UUID()
    ) -> Account {
        Account(
            id: id, name: name, bank: bank, provider: provider, currency: currency, balance: balance,
            iban: nil, maskedPan: nil, color: "#775B88", isArchived: isArchived, isExcluded: false,
            connectionId: connectionId, lowBalanceThreshold: nil, lowBalanceChatId: nil, isCash: isCash)
    }
}

extension Tx {
    static func make(
        _ description: String = "Coffee", amount: Decimal = -12, currency: String = "PLN",
        category: Skarb.Category? = nil, source: String = "sync", isInternal: Bool = false,
        cash: CashLeg? = nil, originalAmount: Decimal? = nil, originalCurrency: String? = nil,
        bank: String = "Test Bank", occurredAt: Date = Date(timeIntervalSince1970: 1_790_000_000),
        id: UUID = UUID()
    ) -> Tx {
        Tx(
            id: id, accountId: .n(1), accountName: "Everyday", accountColor: "#775B88", bank: bank,
            amount: amount, currency: currency, description: description, counterParty: nil, mcc: nil,
            category: category, tags: [], occurredAt: occurredAt, source: source, note: nil,
            isExcluded: false, isInternal: isInternal, cash: cash,
            originalAmount: originalAmount, originalCurrency: originalCurrency)
    }
}

extension Meta {
    static func make(accounts: [Account] = [], categories: [Skarb.Category] = [], tags: [Skarb.Tag] = []) -> Meta {
        Meta(accounts: accounts, categories: categories, tags: tags)
    }
}

/// The stores and services a view model is built from, all over one stub client.
@MainActor
struct TestWorld {
    let http = StubHTTPClient()
    let toasts = ToastCenter()
    let ledger: LedgerStore

    init(meta: Meta = .make()) {
        ledger = LedgerStore(service: LiveLedgerService(http: http))
        http.stub(.get, "/api/meta", with: meta)
    }

    var actions: ActionRunner { ActionRunner(ledger: ledger, toasts: toasts) }
    var transactions: LiveTransactionService { LiveTransactionService(http: http) }
    var tags: LiveTagService { LiveTagService(http: http) }
    var rules: LiveRuleService { LiveRuleService(http: http) }
    var auth: LiveAuthService { LiveAuthService(http: http) }

    /// Loads the stubbed meta into the ledger, as the app does once someone signs in.
    func loaded() async -> TestWorld {
        await ledger.reload()
        return self
    }
}
