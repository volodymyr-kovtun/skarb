using Skarb.Api.Features.Import;

namespace Skarb.Api.Tests;

public class ZenStatementTests
{
    // The layout of a real ZEN export, with every value made up.
    private const string PlnStatement = """
        PLN – Account Statement
        Generated: 26 Oct 2026
        Date: 1 Aug 2026 to 25 Oct 2026

        Account owner
        JANE DOE
        Example Street 1
        "10, Flat 2"
        00-000 Warsaw
        Poland

        Account details
        Local IBAN/Account Number: PL00111122223333444455556666
        Local BIC/SWIFT/SORT CODE: XXXXPLPK
        Global IBAN: GB00XXXX00000000000000
        Global BIC/SWIFT: XXXXGB3L
        Currency: PLN

        Total income:,1310.00,PLN
        Opening balance:,10.00,PLN
        Total outcome:,-1210.00,PLN
        Closing balance:,110.00,PLN


        Transactions:
        Date,Transaction type,Description,Settlement amount,Settlement currency,Original amount,Original currency,Currency rate,Fee description,Fee amount,Fee currency,Balance
        3 Aug 2026,Incoming transfer,"ZEN.COM UAB,   ZEN account top-up ",800.00,PLN,800.00,PLN,1.000000,,,,810.00
        3 Aug 2026,Exchange money,Currency exchange from PLN to EUR,-700.00,PLN,-161.21,EUR,0.230311,,,,110.00
        6 Aug 2026,Card payment,"Some Bistro Warszawa,POL CARD: MASTERCARD *0000",-17.00,PLN,-17.00,PLN,1.000000,,,,93.00
        6 Aug 2026,Card payment,"Some Bistro Warszawa,POL CARD: MASTERCARD *0000",-17.00,PLN,-17.00,PLN,1.000000,,,,76.00
        21 Oct 2026,Incoming transfer,"JANE DOE, EXAMPLE STREET PL IKO BILL PAYMENT PL99000011112222333344445555",500.00,PLN,500.00,PLN,,,,,576.00
        25 Oct 2026,Card payment,"Bookshop Warszawa,POL CARD: MASTERCARD *0000",-466.00,PLN,-466.00,PLN,1.000000,,,,110.00


        This is a computer-generated document. No signature is required.
        "UAB ZEN.COM is an electronic money institution. Registered address: Somewhere 1, Vilnius."
        """;

    [Fact]
    public void Reads_the_wallet_details_above_the_table()
    {
        var s = ZenStatementParser.Parse(PlnStatement);

        Assert.Equal("PLN", s.Currency);
        Assert.Equal("PL00111122223333444455556666", s.Iban); // the local one, not the shared global IBAN
        Assert.Equal(110.00m, s.ClosingBalance);
    }

    [Fact]
    public void A_bare_polish_account_number_gets_its_country_code()
    {
        Assert.Equal("PL00111122223333444455556666", ZenStatementParser.LocalIban("00111122223333444455556666"));
        Assert.Equal("LT000000000000000001", ZenStatementParser.LocalIban("LT00 0000 0000 0000 0001"));
    }

    [Fact]
    public void Reads_every_transaction_and_nothing_from_the_preamble_or_footer()
    {
        var s = ZenStatementParser.Parse(PlnStatement);

        Assert.Empty(s.Errors);
        Assert.Equal(6, s.Rows.Count);
        Assert.Equal([800.00m, -700.00m, -17.00m, -17.00m, 500.00m, -466.00m], s.Rows.Select(r => r.Amount));
        Assert.All(s.Rows, r => Assert.Equal("PLN", r.Currency));
        Assert.Equal(new DateTime(2026, 8, 3, 0, 0, 0, DateTimeKind.Utc), s.Rows[0].OccurredAtUtc);
        Assert.Equal(DateTimeKind.Utc, s.Rows[0].OccurredAtUtc.Kind);
    }

    [Fact]
    public void An_exchange_keeps_the_other_wallets_side_as_its_original_amount()
    {
        var exchange = ZenStatementParser.Parse(PlnStatement).Rows[1];

        Assert.Equal("Exchange money", exchange.TypeCode);
        Assert.Equal(-161.21m, exchange.OriginalAmount);
        Assert.Equal("EUR", exchange.OriginalCurrency);
    }

    [Fact]
    public void An_original_amount_in_the_wallets_own_currency_is_not_kept()
    {
        var topUp = ZenStatementParser.Parse(PlnStatement).Rows[0];

        Assert.Null(topUp.OriginalAmount);
        Assert.Null(topUp.OriginalCurrency);
    }

    [Fact]
    public void A_transfer_naming_an_account_carries_it_as_the_counter_iban()
    {
        var rows = ZenStatementParser.Parse(PlnStatement).Rows;

        Assert.Equal("PL99000011112222333344445555", rows[4].CounterIban);
        Assert.Null(rows[0].CounterIban);
        Assert.All(rows.Where(r => r.TypeCode == "Card payment"), r => Assert.Null(r.CounterIban));
    }

    [Fact]
    public void Ids_match_what_the_generic_import_gives_the_same_row()
    {
        // Statements imported before ZEN had a parser of its own went through the column mapping
        // (date 0, amount 3, description 2). Re-importing them must update those rows, not add twins.
        var seen = new Dictionary<string, int>();
        var expected = CsvImportService.RowId(
            new DateTime(2026, 8, 3, 0, 0, 0, DateTimeKind.Utc), 800.00m, "ZEN.COM UAB,   ZEN account top-up", seen);

        Assert.Equal(expected, ZenStatementParser.Parse(PlnStatement).Rows[0].ExternalId);
    }

    [Fact]
    public void Identical_rows_on_one_day_get_distinct_ids()
    {
        var rows = ZenStatementParser.Parse(PlnStatement).Rows;

        Assert.NotEqual(rows[2].ExternalId, rows[3].ExternalId);
        Assert.Equal(rows[2].ExternalId + "_2", rows[3].ExternalId);
    }

    [Fact]
    public void Runs_of_spaces_in_a_description_are_collapsed()
    {
        Assert.Equal("ZEN.COM UAB, ZEN account top-up", ZenStatementParser.Parse(PlnStatement).Rows[0].Description);
    }

    [Fact]
    public void A_file_without_the_transaction_table_is_refused()
    {
        Assert.Throws<InvalidOperationException>(() =>
            ZenStatementParser.Parse("Date,Amount,Description\n2026-08-03,-10.00,Coffee\n"));
    }
}
