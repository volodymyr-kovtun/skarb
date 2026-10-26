import Foundation
import Testing
@testable import Skarb

struct BulkSelectionTests {
    @Test func a_row_toggles_in_and_out() {
        var selection = BulkSelection()
        selection.toggle(.n(1))
        #expect(selection.contains(.n(1)))
        selection.toggle(.n(1))
        #expect(selection.isEmpty)
    }

    @Test func select_day_fills_the_gaps_and_clear_day_empties_a_full_one() {
        var selection = BulkSelection()
        selection.toggle(.n(1))
        let day = [UUID.n(1), .n(2), .n(3)]

        #expect(!selection.containsAll(day))
        selection.toggleAll(day)
        #expect(selection.count == 3)

        selection.toggleAll(day)
        #expect(selection.isEmpty)
    }

    @Test func the_selection_outlives_a_day_it_was_not_part_of() {
        var selection = BulkSelection()
        selection.toggle(.n(9))
        selection.toggleAll([.n(1), .n(2)])
        selection.toggleAll([.n(1), .n(2)])
        #expect(selection.ids == [.n(9)])
    }

    @Test func select_all_replaces_rows_picked_by_hand() {
        var selection = BulkSelection()
        selection.toggle(.n(9))
        selection.replace(with: [.n(1), .n(2)])
        #expect(selection.ids == [.n(1), .n(2)])
    }

    @Test func an_empty_day_is_never_fully_selected() {
        #expect(!BulkSelection().containsAll([]))
    }
}

struct BulkActionTests {
    @Test func each_action_sends_only_its_own_field() {
        let food = Skarb.Category.make("Food")
        let trip = Skarb.Tag.make("trip")
        #expect(BulkAction.file(food).patch == BulkPatch(categorySet: true, categoryId: food.id))
        #expect(BulkAction.file(nil).patch == BulkPatch(categorySet: true, categoryId: nil))
        #expect(BulkAction.addTag(trip).patch == BulkPatch(addTagIds: [trip.id]))
        #expect(BulkAction.removeTag(trip).patch == BulkPatch(removeTagIds: [trip.id]))
        #expect(BulkAction.markInternal(false).patch == BulkPatch(isInternal: false))
        #expect(BulkAction.exclude(true).patch == BulkPatch(isExcluded: true))
    }

    @Test func the_toast_finishes_the_sentence() {
        #expect(BulkAction.summary(updated: 1, .exclude(false)) == "1 transaction counted again")
        #expect(BulkAction.summary(updated: 12, .addTag(Skarb.Tag.make("trip"))) == "12 transactions tagged #trip")
        #expect(BulkAction.summary(updated: 3, .file(nil)) == "3 transactions left uncategorized")
    }

    @Test func the_cap_is_only_mentioned_when_it_bit() {
        #expect(BulkAction.capNote(selected: 40, total: 40) == nil)
        #expect(BulkAction.capNote(selected: 5000, total: 5200) == "Selected the newest 5000 of 5200 — the rest is one more pass")
    }

    @Test func the_bulk_body_puts_ids_beside_the_edit() throws {
        let body = BulkBody(ids: [.n(1)], patch: BulkPatch(addTagIds: [.n(2)]))
        let json = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(body)) as? [String: Any])
        #expect(json["ids"] as? [String] == [UUID.n(1).uuidString])
        #expect(json["addTagIds"] as? [String] == [UUID.n(2).uuidString])
        #expect(json["categorySet"] as? Bool == false)
        // Left out, not null: a null isInternal would still mean "leave it alone", but the wire
        // should say only what the edit is.
        #expect(json["isInternal"] == nil)
    }
}

struct AccountGroupingTests {
    @Test func wallets_gather_under_cash_whatever_bank_they_were_filed_under() {
        let groups = AccountGrouping.byInstitution([
            Account.make("PLN", bank: "Manual", currency: "PLN", isCash: true),
            Account.make("EUR", bank: "Cash", currency: "EUR", isCash: true),
        ])
        #expect(groups.map(\.label) == ["Cash"])
        #expect(AccountGrouping.subtitle(for: groups[0]) == "2 wallets · one per currency")
    }

    @Test func the_busiest_institution_comes_first_and_ties_keep_their_order() {
        let groups = AccountGrouping.byInstitution([
            Account.make("a", bank: "Alpha"),
            Account.make("b", bank: "Beta"),
            Account.make("c", bank: "Beta"),
            Account.make("d", bank: "Gamma"),
        ])
        #expect(groups.map(\.label) == ["Beta", "Alpha", "Gamma"])
    }

    @Test func a_mixed_currency_group_has_no_total() {
        #expect(AccountGrouping.singleCurrencyTotal([Account.make("a", currency: "PLN"), Account.make("b", currency: "EUR")]) == nil)
        let one = AccountGrouping.singleCurrencyTotal([
            Account.make("a", currency: "PLN", balance: 10), Account.make("b", currency: "PLN", balance: 5),
        ])
        #expect(one?.total == 15)
    }

    @Test func a_holding_that_exists_never_reads_as_zero_percent() {
        #expect(AccountGrouping.share(of: 1, among: [1, 999]) == "<1%")
        #expect(AccountGrouping.share(of: 500, among: [500, 500]) == "50%")
        // An account in the red takes no width.
        #expect(AccountGrouping.share(of: 100, among: [100, -400]) == "100%")
        #expect(AccountGrouping.share(of: 0, among: [0, -5]) == nil)
    }

    @Test func initials_tell_institutions_apart() {
        #expect(AccountGrouping.initials("PKO Bank Polski") == "PB")
        #expect(AccountGrouping.initials("Monobank") == "MO")
    }
}

struct ReportTests {
    private func dashboard(categories: [Dashboard.CategorySlice] = [], tags: [Dashboard.TagSlice] = [],
                           untagged: Decimal = 0, cashflow: [Dashboard.Month] = [], netWorth: Decimal = 0) -> Dashboard {
        Dashboard(
            currency: "PLN", baseCurrency: "PLN", availableCurrencies: ["PLN"], netWorth: netWorth, accounts: [],
            period: .init(key: .month, start: "2027-03-01", end: "2027-03-15", previousStart: "2027-02-01", previousEnd: "2027-02-15"),
            totals: .init(income: 0, expense: 0, invested: 0, net: 0),
            previous: .init(income: 0, expense: 0, invested: 0),
            allTimeInvested: 0, spendingByCategory: categories, spendingByAccount: [], spendingByTag: tags,
            untaggedSpending: untagged, multiTagCount: 0, cashflow: cashflow, recent: [])
    }

    @Test func more_than_six_slices_roll_the_rest_into_other() {
        let slices = (1...8).map {
            Dashboard.CategorySlice(categoryId: .n($0), name: "c\($0)", emoji: "", color: "#426F50", amount: Decimal(100 - $0))
        }
        let result = SpendingBreakdown.slices(dashboard(categories: slices), by: .category)
        #expect(result.count == 7)
        #expect(result.last?.name == "Other")
        #expect(result.last?.amount == Decimal(92 + 93))
    }

    @Test func untagged_spending_is_a_slice_of_its_own_in_its_place() {
        let tags = [Dashboard.TagSlice(tagId: .n(1), name: "trip", color: "#9F4B25", amount: 50)]
        let result = SpendingBreakdown.slices(dashboard(tags: tags, untagged: 80), by: .tag)
        #expect(result.map(\.name) == ["Untagged", "#trip"])
        #expect(result[0].filter == nil)
        #expect(result[1].filter == TransactionFilter(tagIds: [.n(1)]))
    }

    @Test func the_net_worth_line_walks_back_from_today() {
        let months = [
            Dashboard.Month(month: "2027-01", income: 1000, expense: 400, invested: 100),
            Dashboard.Month(month: "2027-02", income: 1000, expense: 700, invested: 0),
            Dashboard.Month(month: "2027-03", income: 500, expense: 200, invested: 0),
        ]
        let points = NetWorthSeries.points(netWorth: 10_000, cashflow: months)
        #expect(points.map(\.value) == [9_400, 9_700, 10_000])
        #expect(NetWorthSeries.points(netWorth: 1, cashflow: Array(months.prefix(1))).isEmpty)
    }

    @Test func a_comparison_says_which_way_and_against_what() {
        #expect(PeriodComparison.subtitle(value: 120, previous: 100, period: .month) == "+20% on the same days last month")
        #expect(PeriodComparison.subtitle(value: 50, previous: 100, period: .ytd) == "−50% on the same stretch last year")
        #expect(PeriodComparison.subtitle(value: 50, previous: 0, period: .month) == "nothing to compare with")
    }

    @Test func days_group_consecutive_rows() {
        let early = Date(timeIntervalSince1970: 1_790_000_000)
        let rows = [Tx.make(occurredAt: early), Tx.make(occurredAt: early), Tx.make(occurredAt: early.addingTimeInterval(-3 * 86_400))]
        let days = TransactionDay.group(rows) { ISO8601.string($0).prefix(10).description }
        #expect(days.map(\.items.count) == [2, 1])
    }
}

struct RuleOfferMathTests {
    @Test func hand_sorted_rows_are_held_back_until_asked_for() {
        var math = RuleOfferMath(counts: .init(uncategorized: 2, automatic: 3, untouched: 4), applyPast: true, includeUntouched: false)
        #expect(math.changing == 5)
        #expect(math.scope == .automatic)
        #expect(math.breakdown == "2 uncategorized, 3 filed automatically. 4 you sorted by hand stay as they are.")

        math.includeUntouched = true
        #expect(math.changing == 9)
        #expect(math.scope == .all)

        math.applyPast = false
        #expect(math.scope == .none)
    }

    @Test func the_saved_message_counts_what_was_refiled() {
        #expect(RuleOfferMath.savedMessage(applied: 0) == "Rule saved")
        #expect(RuleOfferMath.savedMessage(applied: 1) == "Rule saved · 1 transaction re-filed")
    }
}

struct CSVImportTests {
    @Test func a_file_reads_like_the_browser_reads_it() {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let text = CSVImport.text(from: Data(bom + Array("date,amount\n".utf8)))
        #expect(text == "date,amount\n")

        // A byte that isn't UTF-8 becomes the replacement character rather than a guess at
        // another encoding — what keeps row ids identical between the two clients.
        let latin2 = CSVImport.text(from: Data([0x61, 0xB1, 0x62]))
        #expect(latin2 == "a\u{FFFD}b")
    }

    @Test func a_bank_format_is_named_and_a_plain_table_is_mapped() {
        let zen = CSVImport.request(account: .n(1), content: "x", preset: .zen, columns: CSVPreset.zen.columns, hasHeader: true)
        #expect(zen.format == "zen")

        var columns = CSVPreset.generic.columns
        columns.delimiter = ";"
        let generic = CSVImport.request(account: .n(1), content: "x", preset: .generic, columns: columns, hasHeader: false)
        #expect(generic.format == nil)
        #expect(generic.delimiter == ";")
        #expect(!generic.hasHeader)
    }

    @Test func the_summary_mentions_errors_and_warnings_only_when_there_are_some() {
        #expect(CSVImport.summary(.init(imported: 3, skipped: 1, errors: [], warnings: nil))
            == "Imported 3 transaction(s), 1 duplicate(s) skipped.")
        #expect(CSVImport.summary(.init(imported: 0, skipped: 0, errors: ["Row 2: bad"], warnings: ["Balance differs."]))
            == "Imported 0 transaction(s), 0 duplicate(s) skipped (1 row(s) skipped with errors). Balance differs.")
    }
}

struct ConnectionCopyTests {
    private func connection(provider: String, status: String = "linked", until: Date?) -> Connection {
        Connection(id: .n(1), provider: provider, displayName: "Bank", status: status, lastSyncedAt: nil,
                   lastError: nil, accountCount: 2, consentValidUntil: until, ignoredAccountCount: 0)
    }

    @Test func consent_is_flagged_a_fortnight_before_it_ends() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ConnectionCopy.needsRenewal(connection(provider: ProviderName.enableBanking, until: now.addingTimeInterval(10 * 86_400)), now: now))
        #expect(!ConnectionCopy.needsRenewal(connection(provider: ProviderName.enableBanking, until: now.addingTimeInterval(40 * 86_400)), now: now))
        #expect(ConnectionCopy.needsRenewal(connection(provider: ProviderName.enableBanking, status: "pending", until: nil), now: now))
        #expect(!ConnectionCopy.needsRenewal(connection(provider: ProviderName.monobank, until: nil), now: now))
    }

    @Test func removing_a_connection_says_what_goes_with_it() {
        #expect(ConnectionCopy.deleteWarning(connection(provider: ProviderName.monobank, until: nil))
            == "Remove Bank? Its 2 accounts and every transaction on them will be deleted. This cannot be undone.")
    }
}
