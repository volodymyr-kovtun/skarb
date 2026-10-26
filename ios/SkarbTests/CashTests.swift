import Foundation
import Testing
@testable import Skarb

struct CashCorrectionTests {
    private let followsBank = CashLeg(amount: 200, currency: "UAH", corrected: false)
    private let corrected = CashLeg(amount: 45, currency: "EUR", corrected: true)

    @Test func an_untouched_block_sends_nothing() {
        #expect(CashCorrection.decide(leg: followsBank, isInternal: true, currency: "UAH", amountText: "") == .unchanged)
        #expect(CashCorrection.decide(leg: corrected, isInternal: true, currency: "EUR", amountText: "45") == .unchanged)
        #expect(CashCorrection.decide(leg: corrected, isInternal: true, currency: "EUR", amountText: "45.00") == .unchanged)
    }

    @Test func another_currency_with_no_amount_asks_for_todays_rate() {
        #expect(CashCorrection.decide(leg: followsBank, isInternal: true, currency: "EUR", amountText: "")
            == .correct(currency: "EUR", amount: nil))
    }

    @Test func a_typed_amount_is_a_correction() {
        #expect(CashCorrection.decide(leg: followsBank, isInternal: true, currency: "UAH", amountText: "190")
            == .correct(currency: "UAH", amount: 190))
    }

    @Test func clearing_a_correction_goes_back_to_following_the_bank() {
        #expect(CashCorrection.decide(leg: corrected, isInternal: true, currency: "EUR", amountText: "")
            == .correct(currency: "EUR", amount: nil))
    }

    @Test func nothing_rides_along_when_the_withdrawal_stops_being_a_transfer() {
        #expect(CashCorrection.decide(leg: followsBank, isInternal: false, currency: "EUR", amountText: "50") == .unchanged)
    }

    @Test func zero_and_nonsense_are_refused() {
        #expect(CashCorrection.decide(leg: followsBank, isInternal: true, currency: "UAH", amountText: "0")
            == .invalid("The cash you received has to be more than zero."))
        #expect(CashCorrection.decide(leg: followsBank, isInternal: true, currency: "UAH", amountText: "lots")
            == .invalid("The cash you received has to be a number."))
    }

    @Test func the_currency_list_starts_with_what_matters_and_repeats_nothing() {
        let options = CashCorrection.currencyOptions(txCurrency: "UAH", leg: corrected, wallets: ["PLN", "EUR"])
        #expect(Array(options.prefix(3)) == ["UAH", "EUR", "PLN"])
        #expect(Set(options).count == options.count)
        #expect(options.contains("GBP"))
    }

    @Test func the_placeholder_names_the_figure_an_empty_field_stands_for() {
        #expect(CashCorrection.placeholder(txAmount: -200, txCurrency: "UAH", currency: "UAH", estimate: .unknown) == "200.00")
        #expect(CashCorrection.placeholder(txAmount: -200, txCurrency: "UAH", currency: "EUR", estimate: .amount(4.6)) == "≈ 4.60")
        #expect(CashCorrection.placeholder(txAmount: -200, txCurrency: "UAH", currency: "EUR", estimate: .unavailable) == "Amount received")
    }

    @Test func the_hint_says_when_a_wallet_will_open() {
        let hint = CashCorrection.hint(txCurrency: "UAH", currency: "EUR", wallets: ["UAH"], amountText: "", estimate: .unavailable)
        #expect(hint.contains("which opens with it"))
        #expect(hint.contains("no rate"))
    }

    @Test func only_a_correction_is_prefilled() {
        #expect(CashCorrection.initialAmountText(followsBank) == "")
        #expect(CashCorrection.initialAmountText(corrected) == "45")
    }
}

struct CashWalletTests {
    @Test func a_currency_with_a_wallet_is_taken_even_when_the_wallet_is_archived() {
        let accounts = [
            Account.make("PLN", currency: "PLN", isCash: true),
            Account.make("EUR", currency: "EUR", isCash: true, isArchived: true),
            Account.make("Savings", currency: "USD"),
        ]
        #expect(CashWallets.freeCurrencies(in: accounts) == ["UAH", "USD", "GBP", "CZK", "CHF"])
    }

    @Test func only_a_manual_account_in_a_free_currency_can_become_a_wallet() {
        let wallet = Account.make("PLN", currency: "PLN", isCash: true)
        let jar = Account.make("Jar", currency: "PLN")
        let euroJar = Account.make("Euro jar", currency: "EUR")
        let synced = Account.make("Card", provider: ProviderName.monobank, currency: "UAH")
        let all = [wallet, jar, euroJar, synced]
        #expect(CashWallets.canToggleWallet(wallet, among: all))
        #expect(!CashWallets.canToggleWallet(jar, among: all))
        #expect(CashWallets.canToggleWallet(euroJar, among: all))
        #expect(!CashWallets.canToggleWallet(synced, among: all))
    }

    @Test func deleting_a_wallet_points_at_archiving_instead() {
        #expect(AccountCopy.deleteWarning(Account.make("EUR", currency: "EUR", isCash: true)).contains("archive it instead"))
        #expect(AccountCopy.deleteWarning(Account.make("Card", connectionId: .n(1))).contains("Settings can bring it back"))
        #expect(AccountCopy.deleteWarning(Account.make("Jar")).contains("cannot be undone"))
    }
}

struct TransactionDetailsTests {
    @Test func a_withdrawal_says_where_its_cash_went() {
        let plain = Tx.make(amount: -200, currency: "PLN", isInternal: true,
                            cash: CashLeg(amount: 200, currency: "PLN", corrected: false))
        #expect(TransactionDetails.cashNote(plain) == "to cash")

        let abroad = Tx.make(amount: -200, currency: "UAH", isInternal: true,
                             cash: CashLeg(amount: 4.5, currency: "EUR", corrected: true))
        #expect(TransactionDetails.cashNote(abroad) == "to cash as €4.50")

        #expect(TransactionDetails.cashNote(Tx.make(source: TransactionSource.cash, isInternal: true)) == "withdrawal")
    }

    @Test func the_subtitle_names_account_category_and_the_far_side_of_an_exchange() {
        let food = Skarb.Category.make("Food")
        let payment = Tx.make(amount: -700, category: food, originalAmount: -161.21, originalCurrency: "EUR")
        #expect(TransactionDetails.subtitleParts(payment) == ["Test Bank", "Food", "€161.21"])

        let transfer = Tx.make(category: food, isInternal: true)
        #expect(TransactionDetails.subtitleParts(transfer) == ["Test Bank"])
    }

    @Test func deleting_either_half_of_a_withdrawal_says_what_else_goes() {
        let withdrawal = Tx.make(isInternal: true, cash: CashLeg(amount: 1, currency: "PLN", corrected: false))
        #expect(TransactionDetails.deleteQuestion(withdrawal).contains("goes with it"))
        #expect(TransactionDetails.deleteQuestion(Tx.make(source: TransactionSource.cash)).contains("wallet side"))
        #expect(TransactionDetails.deleteQuestion(Tx.make()) == "Delete this transaction?")
    }

    @Test func only_a_move_to_a_new_category_earns_a_rule_offer() {
        let food = Skarb.Category.make("Food")
        let fees = Skarb.Category.make("Fees")
        #expect(TransactionDetails.deservesRuleOffer(before: Tx.make(category: food), after: Tx.make(category: fees)))
        #expect(!TransactionDetails.deservesRuleOffer(before: Tx.make(category: food), after: Tx.make(category: food)))
        #expect(!TransactionDetails.deservesRuleOffer(before: Tx.make(category: food), after: Tx.make()))
        #expect(!TransactionDetails.deservesRuleOffer(before: Tx.make(), after: Tx.make(category: fees, isInternal: true)))
    }
}
