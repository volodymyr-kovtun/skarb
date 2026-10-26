import Foundation
import Testing
@testable import Skarb

struct SessionStoreTests {
    private func signedIn(_ world: TestWorld) async -> SessionStore {
        let session = SessionStore(auth: world.auth)
        world.http.stub(.get, "/api/auth/session", with: Session(authenticated: true, email: "owner@example.com", setupRequired: false))
        await session.load()
        return session
    }

    @Test func a_401_from_a_wrong_current_password_does_not_sign_anyone_out() async {
        let world = TestWorld()
        let session = await signedIn(world)
        // The server still says the session is fine: the 401 was about the password typed.
        await session.revalidate()
        #expect(session.phase == .signedIn(email: "owner@example.com"))
    }

    @Test func a_401_from_a_lapsed_session_drops_to_sign_in() async {
        let world = TestWorld()
        let session = await signedIn(world)
        world.http.stub(.get, "/api/auth/session", with: Session(authenticated: false, email: nil, setupRequired: false))
        await session.revalidate()
        #expect(session.phase == .signedOut)
    }

    @Test func an_unclaimed_instance_asks_for_setup() async {
        let world = TestWorld()
        world.http.stub(.get, "/api/auth/session", with: Session(authenticated: false, email: nil, setupRequired: true))
        let session = SessionStore(auth: world.auth)
        await session.load()
        #expect(session.phase == .setupRequired)
    }

    @Test func listeners_hear_about_each_change_once() async {
        let world = TestWorld()
        let session = SessionStore(auth: world.auth)
        var heard: [AuthPhase] = []
        session.onChange = { heard.append($0) }
        world.http.stub(.get, "/api/auth/session", with: Session(authenticated: true, email: nil, setupRequired: false))
        await session.load()
        await session.load()
        #expect(heard == [.signedIn(email: nil)])
    }
}

struct TransactionsModelTests {
    private func model(_ world: TestWorld) -> TransactionsModel {
        TransactionsModel(transactions: world.transactions, tags: world.tags, rules: world.rules,
                          ledger: world.ledger, toasts: world.toasts)
    }

    @Test func a_bulk_category_change_comes_back_with_an_undo_that_reverts_it() async throws {
        let world = TestWorld()
        let model = model(world)
        let food = Skarb.Category.make("Food")
        let revert = RuleRevert(transactionId: .n(1), previousCategoryId: nil, previousSource: nil)
        world.http.stub(.post, "/api/transactions/bulk", with: BulkResult(updated: 2, reverts: [revert]))

        model.startSelecting(with: .n(1))
        model.toggleDay([.n(1), .n(2)])
        await model.apply(.file(food))

        let bulk = try #require(world.http.calls(to: .post, "/api/transactions/bulk").first?.body)
        #expect(Set(bulk["ids"] as? [String] ?? []) == [UUID.n(1).uuidString, UUID.n(2).uuidString])
        #expect(bulk["categoryId"] as? String == food.id.uuidString)
        #expect(world.toasts.current?.message == "2 transactions filed under 🏷️ Food")
        #expect(world.toasts.current?.undoLabel == "Undo")
        // The selection survives the edit, so the same rows can be tagged next.
        #expect(model.selection.count == 2)

        await world.toasts.runUndo()
        let reverted = try #require(world.http.calls(to: .post, "/api/rules/revert").first?.body)
        #expect((reverted["entries"] as? [[String: Any]])?.first?["transactionId"] as? String == UUID.n(1).uuidString)
    }

    @Test func an_edit_its_opposite_undoes_offers_no_undo() async {
        let world = TestWorld()
        let model = model(world)
        world.http.stub(.post, "/api/transactions/bulk", with: BulkResult(updated: 1, reverts: []))
        model.startSelecting(with: .n(1))
        await model.apply(.exclude(true))
        #expect(world.toasts.current?.message == "1 transaction excluded from stats")
        #expect(world.toasts.current?.undoLabel == nil)
    }

    @Test func select_all_asks_with_the_same_filters_as_the_list() async throws {
        let world = TestWorld()
        let model = model(world)
        world.http.stub(.get, "/api/transactions/ids", with: TransactionIDs(ids: [.n(1), .n(2), .n(3)], total: 3))
        model.filter.accountId = .n(7)
        model.searchText = "zabka"
        model.applySearch()

        model.startSelecting()
        await model.selectAllMatching()

        let call = try #require(world.http.calls(to: .get, "/api/transactions/ids").first)
        #expect(call.query("accountId") == [UUID.n(7).uuidString])
        #expect(call.query("search") == ["zabka"])
        #expect(model.selection.count == 3)
        #expect(world.toasts.current == nil)
    }

    @Test func leaving_selection_mode_forgets_the_selection_and_gives_the_toast_its_place_back() {
        let world = TestWorld()
        let model = model(world)
        model.startSelecting(with: .n(1))
        #expect(world.toasts.clearance == ToastCenter.bulkBarClearance)
        model.stopSelecting()
        #expect(model.selection.isEmpty)
        #expect(world.toasts.clearance == ToastCenter.tabBarClearance)
    }

    @Test func a_link_replaces_the_filters_search_included() {
        let world = TestWorld()
        let model = model(world)
        model.filter.hideInternal = true
        model.searchText = "old"
        model.applySearch()
        model.open(TransactionFilter(tagIds: [.n(3)]))
        #expect(model.activeFilter == TransactionFilter(tagIds: [.n(3)]))
    }
}

struct TransactionEditorModelTests {
    private func editor(_ world: TestWorld, _ tx: Tx?) -> TransactionEditorModel {
        TransactionEditorModel(tx: tx, transactions: world.transactions, tags: world.tags,
                               ledger: world.ledger, actions: world.actions)
    }

    @Test func a_correction_rides_along_and_an_untouched_date_does_not() async throws {
        let world = TestWorld()
        let withdrawal = Tx.make("ATM", amount: -200, currency: "UAH", isInternal: true,
                                 cash: CashLeg(amount: 200, currency: "UAH", corrected: false))
        world.http.stub(.patch, "/api/transactions/\(withdrawal.id.uuidString)", with: withdrawal)
        let model = editor(world, withdrawal)

        model.setCashCurrency("EUR")
        model.cashAmountText = "4.50"
        _ = await model.save()

        let body = try #require(world.http.calls(to: .patch, "/api/transactions/\(withdrawal.id.uuidString)").first?.body)
        #expect(body["cashSet"] as? Bool == true)
        #expect(body["cashCurrency"] as? String == "EUR")
        #expect(body["cashAmount"] as? Double == 4.5)
        #expect(body["occurredAt"] == nil)
        // A synced amount belongs to the bank.
        #expect(body["amount"] == nil)
    }

    @Test func switching_direction_clears_a_category_from_the_other_side() {
        let world = TestWorld()
        let salary = Skarb.Category.make("Salary", kind: .income)
        let model = editor(world, Tx.make(amount: 3000, category: salary))
        #expect(model.direction == .moneyIn)
        #expect(model.categoryId == salary.id)
        model.setDirection(.moneyOut)
        #expect(model.categoryId == nil)
    }

    @Test func a_recategorized_edit_asks_for_a_rule_offer() async throws {
        let world = TestWorld()
        let food = Skarb.Category.make("Food")
        let tx = Tx.make("ZABKA", category: nil)
        var saved = tx
        saved.category = food
        world.http.stub(.patch, "/api/transactions/\(tx.id.uuidString)", with: saved)
        let model = editor(world, tx)
        model.categoryId = food.id

        guard case .updated(let offerFor?) = await model.save() else {
            Issue.record("expected an update that offers a rule")
            return
        }
        #expect(offerFor.category == food)
    }

    @Test func a_new_transaction_needs_an_amount_and_a_description() async {
        let world = await TestWorld(meta: .make(accounts: [Account.make("Wallet")])).loaded()
        let model = editor(world, nil)
        #expect(model.accountId != nil)
        #expect(await model.save() == nil)
        #expect(model.error == "Amount and description are required.")
        #expect(world.http.calls(to: .post, "/api/transactions").isEmpty)
    }
}

struct AccountEditorModelTests {
    @Test func a_wallet_is_created_by_currency_alone() async throws {
        let world = await TestWorld(meta: .make(accounts: [Account.make("PLN", currency: "PLN", isCash: true)])).loaded()
        world.http.stub(.post, "/api/accounts", with: Account.make("EUR", currency: "EUR", isCash: true))
        let model = AccountEditorModel(
            account: nil, startAs: .wallet, accounts: LiveAccountService(http: world.http),
            notifications: LiveNotificationService(http: world.http), ledger: world.ledger, actions: world.actions)

        // PLN already has a wallet, so the first free currency is offered instead.
        #expect(model.walletCurrency == "UAH")
        model.walletCurrency = "EUR"
        model.balanceText = "120,50"
        #expect(await model.save())

        let body = try #require(world.http.calls(to: .post, "/api/accounts").first?.body)
        #expect(body["isCash"] as? Bool == true)
        #expect(body["currency"] as? String == "EUR")
        #expect(body["balance"] as? Double == 120.5)
        #expect(body["name"] == nil)
    }

    @Test func an_alert_with_nobody_to_ping_is_refused_before_it_is_sent() async {
        let world = TestWorld()
        let account = Account.make("Card")
        let model = AccountEditorModel(
            account: account, accounts: LiveAccountService(http: world.http),
            notifications: LiveNotificationService(http: world.http), ledger: world.ledger, actions: world.actions)
        model.threshold = "100"
        #expect(await model.save() == false)
        #expect(model.error?.hasPrefix("Pick who to ping") == true)
        #expect(world.http.calls.isEmpty)
    }
}

struct ServiceContractTests {
    @Test func an_app_authorization_names_its_client_and_the_web_redirect() async throws {
        let http = StubHTTPClient()
        let service = LiveEnableBankingService(http: http)
        let path = "/api/connections/\(UUID.n(5).uuidString)/enablebanking/authorize"

        // Only the request matters here; with nothing stubbed the call throws after recording it.
        _ = try? await service.authorize(.n(5), bank: Aspsp(name: "Test Bank", country: "PL"),
                                         redirectURL: try #require(URL(string: "https://skarb.example.com/settings")))
        let body = try #require(http.calls(to: .post, path).first?.body)
        #expect(body["client"] as? String == "app")
        #expect(body["redirectUrl"] as? String == "https://skarb.example.com/settings")
        #expect(body["aspspName"] as? String == "Test Bank")
    }

    @Test func the_redirect_is_the_web_apps_own_settings_page() throws {
        let defaults = try #require(UserDefaults(suiteName: "skarb.tests.\(UUID().uuidString)"))
        let server = ServerAddress(defaults: defaults)
        server.baseURL = try #require(URL(string: "https://skarb.example.com"))
        #expect(server.bankRedirectURL.absoluteString == "https://skarb.example.com/settings")
    }

    @Test func a_page_asks_with_its_filters_and_its_position() async throws {
        let http = StubHTTPClient()
        http.stub(.get, "/api/transactions", with: Paged<Tx>(items: [], total: 0, page: 2, pageSize: 50))
        _ = try await LiveTransactionService(http: http).page(TransactionFilter(special: .uncategorized), page: 2, pageSize: 50)
        let call = try #require(http.calls.first)
        #expect(call.query("page") == ["2"])
        #expect(call.query("uncategorized") == ["true"])
    }
}
