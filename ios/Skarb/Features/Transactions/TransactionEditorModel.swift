import Foundation
import Observation

/// Add or edit one transaction.
///
/// A synced transaction's amount belongs to the bank, so only a manual one can have it changed —
/// everything else (category, tags, note, whether it counts) is the owner's either way. A
/// withdrawal that was moved to a cash wallet also says what the wallet really received.
@Observable
final class TransactionEditorModel {
    enum Direction: String, CaseIterable, Identifiable {
        case moneyOut, moneyIn
        var id: String { rawValue }
        var label: String { self == .moneyOut ? "Money out" : "Money in" }
    }

    enum Outcome {
        case created
        /// `offerRuleFor` is set when this edit moved the transaction to a category it wasn't in
        /// before — which is what the list needs in order to offer a rule for it.
        case updated(offerRuleFor: Tx?)
        case deleted
    }

    let original: Tx?

    private(set) var direction: Direction = .moneyOut
    var accountId: UUID?
    var amountText = ""
    var descriptionText = ""
    var categoryId: UUID?
    var tagIds: [UUID] = []
    var date = Date()
    var note = ""
    var isExcluded = false
    var isInternal = false
    var newTagName = ""

    /// The cash block: where the withdrawal's cash went, and how much of it.
    private(set) var cashCurrency = ""
    var cashAmountText = ""
    private(set) var estimate: CashCorrection.Estimate = .unknown

    private(set) var busy = false
    private(set) var error: String?

    private let transactions: any TransactionService
    private let tags: any TagService
    private let ledger: LedgerStore
    private let actions: ActionRunner

    init(
        tx: Tx?, transactions: any TransactionService, tags: any TagService,
        ledger: LedgerStore, actions: ActionRunner
    ) {
        original = tx
        self.transactions = transactions
        self.tags = tags
        self.ledger = ledger
        self.actions = actions

        guard let tx else {
            accountId = ledger.activeAccounts.first?.id
            return
        }
        direction = tx.amount > 0 ? .moneyIn : .moneyOut
        accountId = tx.accountId
        amountText = "\(abs(tx.amount))"
        descriptionText = tx.description
        categoryId = tx.category?.id
        tagIds = tx.tags.map(\.id)
        date = tx.occurredAt
        note = tx.note ?? ""
        isExcluded = tx.isExcluded
        isInternal = tx.isInternal
        if let leg = tx.cash {
            cashCurrency = leg.currency
            cashAmountText = CashCorrection.initialAmountText(leg)
        }
    }

    // MARK: - What the form shows

    var isEdit: Bool { original != nil }
    var amountEditable: Bool { original?.isManual ?? true }
    var account: Account? { ledger.account(accountId) }
    var isWalletSide: Bool { original?.isWalletSide ?? false }
    var cashLeg: CashLeg? { original?.cash }

    /// Shown while the withdrawal is still a transfer; un-marking it takes the cash back out.
    var showsCashBlock: Bool { cashLeg != nil && isInternal }
    var showsReleaseWarning: Bool { cashLeg != nil && !isInternal }
    /// The wallet side is derived from its withdrawal, so whether it counts is not its own call.
    var showsCountingToggles: Bool { isEdit && !isWalletSide }

    /// Money out can be an expense or an investment contribution; money in = income categories.
    var categoryChoices: [Category] {
        ledger.categories.filter {
            direction == .moneyOut ? ($0.kind == .expense || $0.kind == .investment) : $0.kind == .income
        }
    }

    var accountChoices: [Account] {
        // An edit can't move a transaction, so the picker only needs to name where it is — even
        // an archived account.
        isEdit ? ledger.accounts : ledger.activeAccounts
    }

    var pickedTagNames: String {
        ledger.tags.filter { tagIds.contains($0.id) }.map { "#\($0.name)" }.joined(separator: " ")
    }

    var cashCurrencyOptions: [String] {
        guard let original, let leg = cashLeg else { return [] }
        return CashCorrection.currencyOptions(txCurrency: original.currency, leg: leg, wallets: ledger.walletCurrencies)
    }

    var cashPlaceholder: String {
        guard let original else { return "" }
        return CashCorrection.placeholder(
            txAmount: original.amount, txCurrency: original.currency, currency: cashCurrency, estimate: estimate)
    }

    var cashHint: String {
        guard let original else { return "" }
        return CashCorrection.hint(
            txCurrency: original.currency, currency: cashCurrency, wallets: ledger.walletCurrencies,
            amountText: cashAmountText, estimate: estimate)
    }

    var releaseWarning: String? { cashLeg.map(CashCorrection.releaseWarning) }

    var deleteQuestion: String { original.map(TransactionDetails.deleteQuestion) ?? "" }

    // MARK: - Editing

    /// Switching between money in and out changes which categories make sense, so it clears the
    /// one picked for the other side.
    func setDirection(_ next: Direction) {
        guard next != direction else { return }
        direction = next
        categoryId = nil
    }

    /// The figure typed for one currency means nothing in the next, and clearing it is what lets
    /// the estimate for the new one show through as the placeholder.
    func setCashCurrency(_ currency: String) {
        guard currency != cashCurrency else { return }
        cashCurrency = currency
        cashAmountText = ""
        estimate = .unknown
    }

    /// A new transaction opened before the shared lists had arrived picks its account the moment
    /// they do, rather than latching whatever was there at first appearance.
    func adoptDefaultAccount() {
        if original == nil, accountId == nil { accountId = ledger.activeAccounts.first?.id }
    }

    /// Today's-rate guess for the currency the cash block names, when it is not the bank's own.
    func loadEstimate() async {
        guard let original, cashLeg != nil, cashCurrency != original.currency else {
            estimate = .unknown
            return
        }
        let currency = cashCurrency
        do {
            let amount = try await transactions.cashEstimate(for: original.id, in: currency)
            guard currency == cashCurrency else { return }
            estimate = amount.map(CashCorrection.Estimate.amount) ?? .unavailable
        } catch {
            if !error.isCancellation { estimate = .unavailable }
        }
    }

    func addTag() async {
        let name = newTagName.trimmed.lowercased()
        guard !name.isEmpty else { return }
        do {
            let tag = try await tags.create(name: name, color: nil)
            ledger.remember(tag)
            if !tagIds.contains(tag.id) { tagIds.append(tag.id) }
            newTagName = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Saving

    func save() async -> Outcome? {
        guard !busy else { return nil }
        error = nil
        guard let accountId else { return fail("Pick an account.") }

        let magnitude = MoneyInput(amountText).decimal ?? 0
        let signed = (direction == .moneyOut ? -1 : 1) * abs(magnitude)
        if amountEditable, signed == 0 { return fail("Amount and description are required.") }
        guard !descriptionText.trimmed.isEmpty else { return fail("Amount and description are required.") }

        var cash = CashCorrection.Decision.unchanged
        if let leg = cashLeg {
            cash = CashCorrection.decide(
                leg: leg, isInternal: isInternal, currency: cashCurrency, amountText: cashAmountText)
            if case .invalid(let message) = cash { return fail(message) }
        }

        busy = true
        defer { busy = false }
        do {
            if let original {
                var patch = TransactionPatch(
                    description: descriptionText.trimmed,
                    amount: amountEditable ? signed : nil,
                    // An untouched date is not sent: re-saving a note must not move a synced
                    // transaction's timestamp to noon.
                    occurredAt: DayStamp.isSameDay(date, original.occurredAt) ? nil : DayStamp.noonUTC(of: date),
                    note: note,
                    isExcluded: isExcluded,
                    isInternal: isInternal,
                    categorySet: true,
                    categoryId: categoryId,
                    tagIds: tagIds)
                if case .correct(let currency, let amount) = cash {
                    patch.cashSet = true
                    patch.cashCurrency = currency
                    patch.cashAmount = amount
                }
                let saved = try await transactions.update(original.id, patch)
                await ledger.invalidate()
                return .updated(offerRuleFor: TransactionDetails.deservesRuleOffer(before: original, after: saved) ? saved : nil)
            }

            _ = try await transactions.create(NewTransaction(
                accountId: accountId,
                amount: signed,
                description: descriptionText.trimmed,
                categoryId: categoryId,
                tagIds: tagIds,
                occurredAt: DayStamp.noonUTC(of: date),
                note: note.trimmed.isEmpty ? nil : note.trimmed))
            await ledger.invalidate()
            return .created
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
            return nil
        }
    }

    func delete() async -> Outcome? {
        guard let original else { return nil }
        let done = await actions.perform("Transaction deleted") {
            try await transactions.delete(original.id)
        }
        return done ? .deleted : nil
    }

    private func fail(_ message: String) -> Outcome? {
        error = message
        return nil
    }
}

extension AppContainer {
    func makeTransactionEditor(for tx: Tx?) -> TransactionEditorModel {
        TransactionEditorModel(tx: tx, transactions: transactions, tags: tags, ledger: ledger, actions: actions)
    }
}
