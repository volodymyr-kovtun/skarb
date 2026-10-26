import Foundation
import Testing
@testable import Skarb

struct TransactionFilterTests {
    @Test func an_empty_filter_asks_for_nothing() {
        #expect(TransactionFilter().queryItems.isEmpty)
        #expect(TransactionFilter().isEmpty)
    }

    @Test func several_tags_are_repeated_parameters() {
        let filter = TransactionFilter(tagIds: [.n(1), .n(2)])
        #expect(filter.queryItems.filter { $0.name == "tagIds" }.map(\.value) == [UUID.n(1).uuidString, UUID.n(2).uuidString])
    }

    @Test func asking_for_internal_transfers_wins_over_hiding_them() {
        var filter = TransactionFilter(special: .internalOnly, hideInternal: true)
        #expect(filter.queryItems.map(\.name) == ["internalOnly"])
        #expect(!filter.canHideInternal)

        filter.special = .uncategorized
        #expect(Set(filter.queryItems.map(\.name)) == ["uncategorized", "hideInternal"])
    }

    @Test func the_key_is_the_same_for_the_same_question() {
        let a = TransactionFilter(search: "zabka", accountId: .n(3))
        let b = TransactionFilter(search: "zabka", accountId: .n(3))
        #expect(a.key == b.key)
        #expect(a.key != TransactionFilter(search: "zabka").key)
    }
}

struct DeepLinkTests {
    @Test func a_transactions_link_opens_on_its_filters() throws {
        let url = try #require(URL(string:
            "skarb://transactions?account=\(UUID.n(1).uuidString)&tags=\(UUID.n(2).uuidString)&tags=\(UUID.n(3).uuidString)"))
        #expect(DeepLink(url) == .transactions(TransactionFilter(accountId: .n(1), tagIds: [.n(2), .n(3)])))
    }

    @Test func a_garbled_id_is_ignored_rather_than_failing_the_link() throws {
        let url = try #require(URL(string: "skarb://transactions?account=not-an-id"))
        #expect(DeepLink(url) == .transactions(TransactionFilter()))
    }

    @Test func links_for_other_apps_are_not_ours() throws {
        #expect(DeepLink(try #require(URL(string: "https://skarb.example.com/transactions"))) == nil)
        #expect(DeepLink(try #require(URL(string: "skarb://somewhere-else"))) == nil)
    }
}

struct EnableBankingHandoffTests {
    @Test func an_app_state_carries_the_connection_and_the_code() throws {
        let url = try #require(URL(string: "skarb://enablebanking?code=abc123&state=app:\(UUID.n(9).uuidString)"))
        #expect(EnableBankingHandoff.outcome(from: url) == .authorized(connection: .n(9), code: "abc123"))
    }

    @Test func a_percent_encoded_state_reads_the_same() throws {
        let url = try #require(URL(string: "skarb://enablebanking?state=app%3A\(UUID.n(9).uuidString)&code=xyz"))
        #expect(EnableBankingHandoff.outcome(from: url) == .authorized(connection: .n(9), code: "xyz"))
    }

    @Test func a_refusal_says_what_the_bank_said() throws {
        let url = try #require(URL(string: "skarb://enablebanking?error=access_denied&state=app:\(UUID.n(9).uuidString)"))
        #expect(EnableBankingHandoff.outcome(from: url) == .refused("The bank didn't grant access: access denied."))
    }

    @Test func a_web_state_is_not_one_the_app_can_finish() throws {
        let url = try #require(URL(string: "skarb://enablebanking?code=abc&state=\(UUID.n(9).uuidString)"))
        guard case .refused = EnableBankingHandoff.outcome(from: url) else {
            Issue.record("expected a refusal")
            return
        }
    }

    @Test func the_link_handler_routes_a_bank_answer_to_the_bank_flow() throws {
        let url = try #require(URL(string: "skarb://enablebanking?code=c&state=app:\(UUID.n(4).uuidString)"))
        #expect(DeepLink(url) == .enableBanking(.authorized(connection: .n(4), code: "c")))
    }
}

struct InputTests {
    @Test(arguments: [
        ("12.50", Decimal(string: "12.5")!),
        ("12,50", Decimal(string: "12.5")!),
        ("1 240,50", Decimal(string: "1240.5")!),
        ("1,240.50", Decimal(string: "1240.5")!),
        ("1.240,50", Decimal(string: "1240.5")!),
        ("-30", Decimal(-30)),
    ])
    func amounts_are_read_the_way_they_were_meant(text: String, value: Decimal) {
        #expect(MoneyInput(text) == .value(value))
    }

    @Test func blank_and_nonsense_are_told_apart() {
        #expect(MoneyInput("  ") == .empty)
        #expect(MoneyInput("abc") == .invalid)
        #expect(MoneyInput("5-3") == .invalid)
        #expect(MoneyInput("1.2.3") == .invalid)
    }

    @Test func a_server_address_is_read_as_typed() {
        #expect(ServerAddressInput.normalize("skarb.example.com/")?.absoluteString == "https://skarb.example.com")
        #expect(ServerAddressInput.normalize("http://192.168.1.4:5178")?.absoluteString == "http://192.168.1.4:5178")
        #expect(ServerAddressInput.normalize("   ") == nil)
    }

    @Test func authenticator_codes_keep_six_digits() {
        #expect(CredentialPolicy.totpDigits("123 456 789") == "123456")
        #expect(CredentialPolicy.totpDigits("code: 042") == "042")
    }

    @Test func a_picked_day_is_noon_utc_on_that_calendar_day() throws {
        var warsaw = Calendar(identifier: .gregorian)
        warsaw.timeZone = try #require(TimeZone(identifier: "Europe/Warsaw"))
        // 00:30 on 3 March in Warsaw is still 2 March in UTC; the day picked is the 3rd.
        let picked = try #require(warsaw.date(from: DateComponents(year: 2027, month: 3, day: 3, hour: 0, minute: 30)))
        #expect(ISO8601.string(DayStamp.noonUTC(of: picked, in: warsaw)) == "2027-03-03T12:00:00Z")
    }
}
