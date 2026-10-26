import Foundation
import Observation

/// Add a manual account or a cash wallet, or change one that exists. A synced account's name,
/// color and alert are the owner's; its balance and currency belong to the bank.
@Observable
final class AccountEditorModel {
    /// What the add sheet opens as. A wallet is not a kind of bank account, so it gets its own form.
    enum Kind: String, CaseIterable, Identifiable {
        case account, wallet
        var id: String { rawValue }
        var label: String { self == .account ? "Account" : "Cash wallet" }
    }

    let original: Account?
    var kind: Kind
    var name = ""
    var bank = ""
    var currency = "PLN"
    var walletCurrency = ""
    var balanceText = "0"
    var color = Palette.accountColors[0]
    var isArchived = false
    var isExcluded = false
    var isCash = false
    var threshold = ""
    var alertChat = ""

    private(set) var chats: [TelegramChat] = []
    private(set) var telegram: TelegramSettings?
    private(set) var telegramNote: StatusMessage?
    private(set) var telegramBusy = false
    private(set) var busy = false
    private(set) var error: String?

    private let accounts: any AccountService
    private let notifications: any NotificationService
    private let ledger: LedgerStore
    private let actions: ActionRunner

    init(
        account: Account?, startAs kind: Kind = .account,
        accounts: any AccountService, notifications: any NotificationService,
        ledger: LedgerStore, actions: ActionRunner
    ) {
        original = account
        self.kind = kind
        self.accounts = accounts
        self.notifications = notifications
        self.ledger = ledger
        self.actions = actions

        walletCurrency = CashWallets.freeCurrencies(in: ledger.accounts).first ?? ""
        guard let account else { return }
        name = account.name
        color = account.color
        isArchived = account.isArchived
        isExcluded = account.isExcluded
        isCash = account.isCash
        threshold = account.lowBalanceThreshold.map { "\($0)" } ?? ""
        alertChat = account.lowBalanceChatId ?? ""
    }

    var isEdit: Bool { original != nil }
    var addsWallet: Bool { !isEdit && kind == .wallet }
    var freeCurrencies: [String] { CashWallets.freeCurrencies(in: ledger.accounts) }

    var canToggleWallet: Bool {
        guard let original else { return false }
        return CashWallets.canToggleWallet(original, among: ledger.accounts)
    }

    var title: String {
        isEdit ? "Edit account" : (addsWallet ? "Add cash wallet" : "Add manual account")
    }

    var deleteWarning: String { original.map(AccountCopy.deleteWarning) ?? "" }

    /// The alert section only asks for a recipient once there is a limit to alert on.
    var alertsOn: Bool { !threshold.trimmed.isEmpty }

    var botMissing: Bool { telegram.map { !$0.hasToken } ?? false }

    // MARK: - Telegram

    /// Only to warn when an alert is configured but has nowhere to go.
    func loadTelegram() async {
        guard isEdit else { return }
        telegram = try? await notifications.telegramSettings()
    }

    func findChats() async {
        await runTelegram {
            chats = try await notifications.telegramChats()
            if chats.isEmpty {
                telegramNote = StatusMessage(ok: false, text: "No chats found. The recipient has to open the bot in Telegram and send it anything first — messages only show up here for about a day.")
            }
        }
    }

    func pick(_ chat: TelegramChat) {
        alertChat = chat.id
        chats = []
        telegramNote = nil
    }

    func sendTest() async {
        await runTelegram {
            let sentTo = try await notifications.telegramTest(chatId: alertChat.trimmed)
            telegramNote = StatusMessage(ok: true, text: "Test sent to chat \(sentTo) — check Telegram.")
        }
    }

    private func runTelegram(_ body: () async throws -> Void) async {
        telegramBusy = true
        telegramNote = nil
        defer { telegramBusy = false }
        do { try await body() } catch { telegramNote = StatusMessage(ok: false, text: error.localizedDescription) }
    }

    // MARK: - Saving

    func save() async -> Bool {
        guard !busy else { return false }
        error = nil
        let balance = MoneyInput(balanceText).decimal ?? 0
        let request: () async throws -> Void

        if let original {
            let limit: Decimal?
            switch MoneyInput(threshold) {
            case .empty: limit = nil
            case .value(let value): limit = value
            case .invalid: return fail("The alert limit has to be a number.")
            }
            if limit != nil, alertChat.trimmed.isEmpty {
                return fail("Pick who to ping — Find chats lists everyone who has messaged the bot.")
            }
            let patch = AccountPatch(
                name: name.trimmed, color: color, isArchived: isArchived, isExcluded: isExcluded,
                lowBalanceSet: true, lowBalanceThreshold: limit,
                lowBalanceChatId: alertChat.trimmed.isEmpty ? nil : alertChat.trimmed,
                isCash: canToggleWallet ? isCash : nil)
            request = { [accounts] in _ = try await accounts.update(original.id, patch) }
        } else if addsWallet {
            guard !walletCurrency.isEmpty else { return fail("Every currency Skarb lists already has a wallet.") }
            let body = NewAccount(currency: walletCurrency, balance: balance, color: color, isCash: true)
            request = { [accounts] in _ = try await accounts.create(body) }
        } else {
            guard !name.trimmed.isEmpty else { return fail("Give the account a name.") }
            let body = NewAccount(name: name.trimmed, bank: bank.trimmed, currency: currency, balance: balance, color: color)
            request = { [accounts] in _ = try await accounts.create(body) }
        }

        busy = true
        defer { busy = false }
        do {
            try await request()
            await ledger.invalidate()
            return true
        } catch {
            return fail(error.localizedDescription)
        }
    }

    func delete() async -> Bool {
        guard let original else { return false }
        return await actions.perform("Account deleted") {
            try await accounts.delete(original.id)
        }
    }

    private func fail(_ message: String) -> Bool {
        error = message
        return false
    }
}

extension AppContainer {
    func makeAccountEditor(for account: Account?, startAs kind: AccountEditorModel.Kind = .account) -> AccountEditorModel {
        AccountEditorModel(
            account: account, startAs: kind, accounts: accounts, notifications: notifications,
            ledger: ledger, actions: actions)
    }
}
