using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Tests;

public class ExchangePairingTests
{
    private static readonly TimeSpan Window = TimeSpan.FromHours(72);
    private static readonly DateTime Day = new(2026, 8, 3, 0, 0, 0, DateTimeKind.Utc);
    private static readonly Guid PlnWallet = Guid.Parse("aaaaaaaa-0000-0000-0000-000000000001");
    private static readonly Guid EurWallet = Guid.Parse("bbbbbbbb-0000-0000-0000-000000000002");

    private static Transaction Leg(
        decimal amount, string currency, Guid account, decimal? original = null, string? originalCurrency = null,
        string type = "Exchange money", DateTime? at = null) =>
        new()
        {
            Amount = amount, Currency = currency, AccountId = account, OccurredAt = at ?? Day,
            TypeCode = type, Description = "Currency exchange transaction",
            OriginalAmount = original, OriginalCurrency = originalCurrency,
        };

    [Fact]
    public void The_selling_leg_naming_what_it_bought_pairs_them()
    {
        // ZEN "from PLN to EUR": the PLN side records the euros; the EUR side records only itself.
        var sold = Leg(-700.00m, "PLN", PlnWallet, -161.21m, "EUR");
        var bought = Leg(161.21m, "EUR", EurWallet);

        var pair = Assert.Single(TransferDetector.PairExchanges([sold, bought], Window));
        Assert.Same(sold, pair.Debit);
        Assert.Same(bought, pair.Credit);
    }

    [Fact]
    public void The_buying_leg_naming_what_it_sold_pairs_them_too()
    {
        // ZEN "from EUR to PLN": here it is the credited side that carries the far amount.
        var sold = Leg(-2.27m, "EUR", EurWallet);
        var bought = Leg(9.86m, "PLN", PlnWallet, 2.27m, "EUR");

        Assert.Single(TransferDetector.PairExchanges([sold, bought], Window));
    }

    [Fact]
    public void A_near_miss_on_the_amount_is_not_a_pair()
    {
        var sold = Leg(-700.00m, "PLN", PlnWallet, -161.21m, "EUR");
        var bought = Leg(161.22m, "EUR", EurWallet);

        Assert.Empty(TransferDetector.PairExchanges([sold, bought], Window));
    }

    [Fact]
    public void A_card_payment_abroad_is_not_the_other_half_of_a_same_size_credit()
    {
        // Paying 10 USD from the PLN wallet records -10 USD as its original too — but a 10 USD
        // refund landing elsewhere is not the other side of anything.
        var payment = Leg(-43.12m, "PLN", PlnWallet, -10.00m, "USD", type: "Card payment");
        payment.Description = "Some Shop";
        var credit = Leg(10.00m, "USD", EurWallet, type: "Incoming transfer");
        credit.Description = "Refund";

        Assert.Empty(TransferDetector.PairExchanges([payment, credit], Window));
    }

    [Fact]
    public void Legs_on_the_same_account_never_pair()
    {
        var sold = Leg(-700.00m, "PLN", PlnWallet, -161.21m, "EUR");
        var bought = Leg(161.21m, "EUR", PlnWallet);

        Assert.Empty(TransferDetector.PairExchanges([sold, bought], Window));
    }

    [Fact]
    public void Exchanges_outside_the_window_do_not_pair()
    {
        var sold = Leg(-700.00m, "PLN", PlnWallet, -161.21m, "EUR");
        var bought = Leg(161.21m, "EUR", EurWallet, at: Day.AddDays(4));

        Assert.Empty(TransferDetector.PairExchanges([sold, bought], Window));
    }

    [Fact]
    public void Two_identical_exchanges_pair_each_with_its_own_day()
    {
        var firstSold = Leg(-700.00m, "PLN", PlnWallet, -161.21m, "EUR");
        var firstBought = Leg(161.21m, "EUR", EurWallet);
        var secondSold = Leg(-700.00m, "PLN", PlnWallet, -161.21m, "EUR", at: Day.AddDays(2));
        var secondBought = Leg(161.21m, "EUR", EurWallet, at: Day.AddDays(2));

        var pairs = TransferDetector.PairExchanges([secondBought, firstSold, secondSold, firstBought], Window);

        Assert.Equal(2, pairs.Count);
        Assert.Contains(pairs, p => p.Debit == firstSold && p.Credit == firstBought);
        Assert.Contains(pairs, p => p.Debit == secondSold && p.Credit == secondBought);
    }
}

public class DetectionStartTests
{
    private static readonly DateTime Cutoff = new(2026, 10, 12, 0, 0, 0, DateTimeKind.Utc);
    private static readonly TimeSpan Window = TimeSpan.FromHours(72);

    [Fact]
    public void Nothing_new_and_old_keeps_the_lookback_cutoff()
    {
        Assert.Equal(Cutoff, TransferDetector.DetectionStart(Cutoff, Window, null));
        Assert.Equal(Cutoff, TransferDetector.DetectionStart(Cutoff, Window, Cutoff.AddDays(3)));
    }

    [Fact]
    public void An_imported_statement_reaches_back_to_its_first_row_less_the_pair_window()
    {
        var firstImportedRow = new DateTime(2026, 8, 3, 0, 0, 0, DateTimeKind.Utc);

        Assert.Equal(firstImportedRow - Window, TransferDetector.DetectionStart(Cutoff, Window, firstImportedRow));
    }
}
