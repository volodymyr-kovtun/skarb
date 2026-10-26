import Foundation

/// The "Cash you received" block on a withdrawal that was moved to a cash wallet.
///
/// The bank only knows what left the account: a UAH card in an Italian ATM shows hryvnias while
/// the hand holds euros, and the machine's own fee is in the bank's figure without ever reaching
/// the wallet. Neither can be read off the statement, so the owner says — and an untouched block
/// must not freeze today's figure into a correction, or the wallet would stop following the bank's
/// amount when a hold settles.
nonisolated enum CashCorrection {
    enum Decision: Equatable, Sendable {
        /// Nothing changed: send no cash fields at all.
        case unchanged
        /// Send `cashSet` with these. A nil amount means "what the bank says" in the bank's own
        /// currency, and "today's rate, frozen at save" in any other.
        case correct(currency: String, amount: Decimal?)
        case invalid(String)
    }

    /// What saving the editor should do with the block, given what it holds now.
    ///
    /// - Parameter isInternal: the editor's internal toggle. Un-marking a withdrawal takes the cash
    ///   back out of the wallet, so a correction rides along only while it stays a transfer.
    static func decide(leg: CashLeg, isInternal: Bool, currency: String, amountText: String) -> Decision {
        guard isInternal else { return .unchanged }
        let received: Decimal?
        switch MoneyInput(amountText) {
        case .empty: received = nil
        case .value(let value): received = value
        case .invalid: return .invalid("The cash you received has to be a number.")
        }
        let before = leg.corrected ? leg.amount : nil
        guard currency != leg.currency || received != before else { return .unchanged }
        if let received, received <= 0 { return .invalid("The cash you received has to be more than zero.") }
        return .correct(currency: currency, amount: received)
    }

    /// The bank's currency first, then where the cash went, then every wallet and every offered
    /// currency — each once.
    static func currencyOptions(txCurrency: String, leg: CashLeg, wallets: [String]) -> [String] {
        var seen = Set<String>()
        return ([txCurrency, leg.currency] + wallets + Currencies.offered).filter { seen.insert($0).inserted }
    }

    /// What the field starts as: a correction is the only thing prefilled, because an empty field
    /// is how "follow the bank" is said.
    static func initialAmountText(_ leg: CashLeg) -> String {
        leg.corrected ? "\(leg.amount)" : ""
    }

    /// Today's-rate guess at what another currency's ATM paid out.
    enum Estimate: Equatable, Sendable {
        /// Not asked for (the bank's own currency) or still loading.
        case unknown
        /// The server has no rate for one of the two currencies.
        case unavailable
        case amount(Decimal)
    }

    /// The grey text in the empty field — the figure an empty field stands for.
    static func placeholder(txAmount: Decimal, txCurrency: String, currency: String, estimate: Estimate) -> String {
        if currency == txCurrency { return plain(abs(txAmount)) }
        if case .amount(let value) = estimate { return "≈ \(plain(value))" }
        return "Amount received"
    }

    /// The sentence under the field.
    static func hint(
        txCurrency: String, currency: String, wallets: [String], amountText: String, estimate: Estimate
    ) -> String {
        if currency == txCurrency {
            return "This withdrawal went to your \(currency) cash wallet instead of counting as spending. "
                + "Took it out abroad, or the ATM kept a fee? Say what you were actually handed."
        }
        let opens = wallets.contains(currency) ? "" : ", which opens with it"
        let lead = "Goes to your \(currency) cash wallet\(opens). "
        switch estimate {
        case .unavailable:
            return lead + "Skarb has no rate for it, so the amount is yours to fill in."
        case .amount(let value) where amountText.trimmingCharacters(in: .whitespaces).isEmpty:
            return lead + "Leave the amount empty to use today's rate — about "
                + "\(Format.money(value, currency)) — or type what the ATM really paid out."
        default:
            return lead + "The rate is only a guess: fees and the bank's own spread are why the real figure differs."
        }
    }

    /// Shown when the internal toggle is switched off on a withdrawal: saving undoes the move.
    static func releaseWarning(_ leg: CashLeg) -> String {
        "Saving this takes \(Format.money(leg.amount, leg.currency)) back out of your cash wallet "
            + "and counts the withdrawal as spending."
    }

    private static func plain(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        return String(format: "%.2f", number.doubleValue)
    }
}
