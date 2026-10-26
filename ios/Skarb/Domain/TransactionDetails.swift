import Foundation

/// What a transaction row says about itself, beyond its name and amount.
nonisolated enum TransactionDetails {
    /// The pieces of the line under a transaction's name, in order: where it happened, what it
    /// was filed as, where its cash went, and what it was worth in another currency.
    static func subtitleParts(_ tx: Tx) -> [String] {
        var parts = [tx.bank.isEmpty ? tx.accountName : tx.bank]
        if !tx.isInternal, let category = tx.category { parts.append(category.name) }
        if tx.isInternal, let note = cashNote(tx) { parts.append(note) }
        // An exchange leg says what it turned into; a payment abroad, what it cost there.
        if let original = originalAmount(tx) { parts.append(original) }
        return parts
    }

    /// Where a withdrawal's cash went. The amount is only spelled out when it is not simply the
    /// bank's own — an ATM abroad, or one that kept a fee.
    static func cashNote(_ tx: Tx) -> String? {
        if tx.isWalletSide { return "withdrawal" }
        guard let cash = tx.cash else { return nil }
        let same = cash.currency == tx.currency && cash.amount == -tx.amount
        return same ? "to cash" : "to cash as \(Format.money(cash.amount, cash.currency))"
    }

    static func originalAmount(_ tx: Tx) -> String? {
        guard let amount = tx.originalAmount, let currency = tx.originalCurrency, !currency.isEmpty
        else { return nil }
        return Format.money(abs(amount), currency)
    }

    /// Deleting either half of a cash withdrawal takes the pairing with it, so the question says
    /// what else goes.
    static func deleteQuestion(_ tx: Tx) -> String {
        if tx.isWalletSide {
            return "Delete the wallet side? The withdrawal it belongs to goes back to counting as spending."
        }
        if tx.cash != nil { return "Delete this withdrawal? The cash it put in your wallet goes with it." }
        return "Delete this transaction?"
    }

    /// Only a move to a real category is worth generalising into a rule — clearing one, or
    /// re-saving the category it already had, teaches nothing, and keyword rules never run on
    /// transfers between your own accounts.
    static func deservesRuleOffer(before: Tx, after: Tx) -> Bool {
        guard let category = after.category else { return false }
        return category.id != before.category?.id && !after.isInternal
    }
}
