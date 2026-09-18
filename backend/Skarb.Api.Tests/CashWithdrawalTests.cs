using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Tests;

public class CashWithdrawalTests
{
    private const string Cash = CashWithdrawal.CategoryKey;

    private static Transaction Row(decimal amount = -2000, string currency = "UAH") =>
        new() { Amount = amount, Currency = currency, Source = TransactionSources.Sync };

    private static CashMove Decide(Transaction tx, string? category = Cash, bool onWallet = false) =>
        CashWithdrawal.Decide(tx, category, onWallet);

    [Fact]
    public void Money_out_filed_under_cash_is_moved_to_the_wallet()
    {
        Assert.Equal(CashMove.Mirror, Decide(Row()));
    }

    [Fact]
    public void Only_the_cash_category_makes_a_withdrawal()
    {
        Assert.Equal(CashMove.Leave, Decide(Row(), category: "groceries"));
        Assert.Equal(CashMove.Leave, Decide(Row(), category: null));
    }

    [Fact]
    public void Money_in_is_never_a_withdrawal()
    {
        Assert.Equal(CashMove.Leave, Decide(Row(amount: 2000)));
    }

    [Fact]
    public void Spending_from_the_wallet_is_not_withdrawing_into_it()
    {
        Assert.Equal(CashMove.Leave, Decide(Row(), onWallet: true));
    }

    [Fact]
    public void A_row_the_user_decided_by_hand_is_left_alone_either_way()
    {
        var unmarked = Row();
        unmarked.InternalSource = InternalSources.Manual;
        var marked = Row();
        (marked.IsInternal, marked.InternalSource) = (true, InternalSources.Manual);

        Assert.Equal(CashMove.Leave, Decide(unmarked));
        Assert.Equal(CashMove.Leave, Decide(marked));
    }

    [Fact]
    public void A_withdrawal_that_found_a_real_second_leg_keeps_that_pairing()
    {
        // The wallet top-up was typed in by hand and the pair detector matched it. Writing a
        // second wallet side on top would put the same cash in the wallet twice.
        var paired = Row();
        (paired.IsInternal, paired.InternalSource) = (true, InternalSources.Pair);

        Assert.Equal(CashMove.Leave, Decide(paired));
    }

    [Fact]
    public void An_internal_mark_from_before_provenance_is_not_taken_over()
    {
        var legacy = Row();
        legacy.IsInternal = true;

        Assert.Equal(CashMove.Leave, Decide(legacy));
    }

    [Fact]
    public void A_withdrawal_excluded_by_hand_stays_out_until_it_is_included_again()
    {
        // The workaround from before wallets existed. Un-excluding the row is how it opts in.
        var excluded = Row();
        excluded.IsExcluded = true;
        Assert.Equal(CashMove.Leave, Decide(excluded));

        excluded.IsExcluded = false;
        Assert.Equal(CashMove.Mirror, Decide(excluded));
    }

    [Fact]
    public void A_mirrored_withdrawal_is_restated_on_every_pass()
    {
        var mirrored = Row();
        (mirrored.IsInternal, mirrored.InternalSource) = (true, InternalSources.Cash);

        Assert.Equal(CashMove.Mirror, Decide(mirrored));
    }

    [Fact]
    public void A_mirrored_withdrawal_refiled_elsewhere_is_released()
    {
        var mirrored = Row();
        (mirrored.IsInternal, mirrored.InternalSource) = (true, InternalSources.Cash);

        Assert.Equal(CashMove.Release, Decide(mirrored, category: "fees"));
        Assert.Equal(CashMove.Release, Decide(mirrored, category: null));
    }

    [Fact]
    public void Excluding_a_mirrored_withdrawal_does_not_take_the_cash_back()
    {
        var mirrored = Row();
        (mirrored.IsInternal, mirrored.InternalSource, mirrored.IsExcluded) = (true, InternalSources.Cash, true);

        Assert.Equal(CashMove.Mirror, Decide(mirrored));
    }

    [Fact]
    public void The_wallet_side_is_never_read_as_a_withdrawal_itself()
    {
        var walletSide = new Transaction
        {
            Amount = 2000, Currency = "UAH", Source = TransactionSources.Cash,
            IsInternal = true, InternalSource = InternalSources.Cash,
        };

        // Without the source check this would be "ours, and not money out" — a release, which
        // would strip the mark from the row that exists only because of it.
        Assert.Equal(CashMove.Leave, Decide(walletSide, category: null, onWallet: true));
    }

    [Fact]
    public void The_wallet_receives_exactly_what_left_the_account()
    {
        Assert.Equal(("UAH", 12478.47m), CashWithdrawal.Received(Row(amount: -12478.47m)));
    }

    [Fact]
    public void A_correction_says_what_the_atm_actually_paid_out()
    {
        // A UAH card in an Italian ATM: the statement shows hryvnias, the hand holds euros.
        var abroad = Row(amount: -12478.47m);
        (abroad.CashCurrency, abroad.CashAmount) = ("eur", 250m);

        Assert.Equal(("EUR", 250m), CashWithdrawal.Received(abroad));
    }

    [Fact]
    public void The_wallet_side_is_keyed_by_its_withdrawal_and_nothing_else()
    {
        var tx = Row();
        var key = CashWithdrawal.LegKey(tx);

        // Editing the withdrawal must find the same wallet side again, not write a second one.
        tx.Amount = -2100;
        tx.Description = "settled";
        Assert.Equal(key, CashWithdrawal.LegKey(tx));
        Assert.NotEqual(key, CashWithdrawal.LegKey(Row()));
        Assert.StartsWith("cash", key);
    }
}
