using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Tests;

public class TransferPairingTests
{
    private static readonly TimeSpan Window = TimeSpan.FromHours(72);
    private static readonly DateTime Day = new(2026, 8, 3, 12, 40, 7, DateTimeKind.Utc);
    private static readonly Guid AccountA = Guid.Parse("aaaaaaaa-0000-0000-0000-000000000001");
    private static readonly Guid AccountB = Guid.Parse("bbbbbbbb-0000-0000-0000-000000000002");

    private static Transaction Leg(decimal amount, DateTime at, Guid account, string currency = "UAH") =>
        new() { Amount = amount, OccurredAt = at, AccountId = account, Currency = currency };

    [Fact]
    public void Closest_match_wins_the_credit_over_an_earlier_debit()
    {
        // The real case: an outgoing from a bank connected later sat 62h before the credit and
        // claimed it, leaving the same-second leg unpaired.
        var distant = Leg(-5000, Day.AddHours(-61.81), AccountA);
        var credit = Leg(5000, Day, AccountB);
        var exact = Leg(-5000, Day, AccountA);

        var pairs = TransferDetector.PairLegs([distant, credit, exact], Window);

        var pair = Assert.Single(pairs);
        Assert.Same(exact, pair.Debit);
        Assert.Same(credit, pair.Credit);
    }

    [Fact]
    public void Input_order_does_not_change_the_outcome()
    {
        var distant = Leg(-5000, Day.AddHours(-61.81), AccountA);
        var credit = Leg(5000, Day, AccountB);
        var exact = Leg(-5000, Day, AccountA);

        foreach (var ordering in new[]
                 {
                     new[] { distant, credit, exact },
                     [exact, distant, credit],
                     [credit, exact, distant],
                 })
        {
            var pair = Assert.Single(TransferDetector.PairLegs(ordering, Window));
            Assert.Same(exact, pair.Debit);
        }
    }

    [Fact]
    public void Ties_resolve_the_same_way_every_run()
    {
        var credit = Leg(5000, Day, AccountB);
        var first = Leg(-5000, Day, AccountA);
        var second = Leg(-5000, Day, AccountA);

        var forward = Assert.Single(TransferDetector.PairLegs([first, second, credit], Window));
        var reversed = Assert.Single(TransferDetector.PairLegs([second, first, credit], Window));

        Assert.Same(forward.Debit, reversed.Debit);
    }

    [Fact]
    public void Each_leg_is_used_at_most_once()
    {
        var credit = Leg(5000, Day, AccountB);
        var one = Leg(-5000, Day, AccountA);
        var two = Leg(-5000, Day.AddHours(1), AccountA);

        var pairs = TransferDetector.PairLegs([one, two, credit], Window);

        Assert.Single(pairs);
        Assert.Same(credit, pairs[0].Credit);
    }

    [Fact]
    public void Two_transfers_each_find_their_own_partner()
    {
        var outA = Leg(-5000, Day, AccountA);
        var inA = Leg(5000, Day.AddMinutes(1), AccountB);
        var outB = Leg(-5000, Day.AddDays(1), AccountB);
        var inB = Leg(5000, Day.AddDays(1).AddMinutes(1), AccountA);

        var pairs = TransferDetector.PairLegs([outA, inA, outB, inB], Window);

        Assert.Equal(2, pairs.Count);
        Assert.Contains(pairs, p => p.Debit == outA && p.Credit == inA);
        Assert.Contains(pairs, p => p.Debit == outB && p.Credit == inB);
    }

    [Fact]
    public void Legs_outside_the_window_or_mismatched_never_pair()
    {
        var debit = Leg(-5000, Day, AccountA);

        Assert.Empty(TransferDetector.PairLegs([debit, Leg(5000, Day.AddHours(73), AccountB)], Window));
        Assert.Empty(TransferDetector.PairLegs([debit, Leg(5000, Day, AccountA)], Window));
        Assert.Empty(TransferDetector.PairLegs([debit, Leg(5000, Day, AccountB, "PLN")], Window));
        Assert.Empty(TransferDetector.PairLegs([debit, Leg(4999, Day, AccountB)], Window));
    }

    [Fact]
    public void A_leg_exactly_on_the_window_edge_still_pairs()
    {
        var debit = Leg(-5000, Day, AccountA);
        var credit = Leg(5000, Day.Add(Window), AccountB);

        Assert.Single(TransferDetector.PairLegs([debit, credit], Window));
    }
}
