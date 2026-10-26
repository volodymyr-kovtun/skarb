using Skarb.Api.Common.Services;

namespace Skarb.Api.Tests;

public class RuleMatchingTests
{
    [Theory]
    [InlineData("ZUS", "zus", true)]                                     // exact word
    [InlineData("Składka ZUS DRA za maj", "zus", true)]                  // word inside sentence
    [InlineData("MIA CONSULTZUSA SP Z O.O.", "zus", false)]              // glued mid-word — must NOT match
    [InlineData("MEDICOVER SP. Z O.O.", "doz", false)]                   // 'doz' inside 'MEDICOVER'? no — but guards similar cases
    [InlineData("URZĄD SKARBOWY WARSZAWA", "urząd skarbowy", true)]      // multi-word, diacritics
    [InlineData("APPLE.COM/BILL 866-712-7753", "apple.com/bill", true)]  // punctuation-edged pattern
    [InlineData("OPŁATA ZA PROWADZENIE RACHUNKU FEE", "fee", true)]      // type code at end
    [InlineData("COFFEE HOUSE", "fee", false)]                           // 'fee' inside 'COFFEE' — no
    [InlineData("bp station", "bp", true)]                               // short token as its own word
    [InlineData("bpstation", "bp", false)]                               // short token glued — no
    public void Matches_respects_word_boundaries_on_alphanumeric_edges(string haystack, string pattern, bool expected)
    {
        Assert.Equal(expected, RuleBasedCategorizer.Matches(haystack, pattern));
    }

    [Fact]
    public void A_zen_card_row_keeps_whole_word_matching()
    {
        // ZEN's "Card payment" descriptors keep their spaces; PKO's glued ones are what the
        // substring fallback is for, and they come with an uppercase "CARD-…" code.
        const string zen = "AROMA COFFEE WARSZAWA,POL CARD: MASTERCARD *0000";
        var haystack = RuleBasedCategorizer.Haystack(zen, null, null, "Card payment");

        Assert.False(RuleBasedCategorizer.RuleHits(haystack, "Card payment", "fee"));
        Assert.True(RuleBasedCategorizer.RuleHits(haystack, "Card payment", "coffee"));
        Assert.True(RuleBasedCategorizer.RuleHits("WARSZAWAFOUNDATIONCOFFEE.PL", "CARD-PAYMENT", "coffee"));
    }

    [Fact]
    public void Matches_is_case_insensitive()
    {
        Assert.True(RuleBasedCategorizer.Matches("biedronka 7184", "BIEDRONKA"));
        Assert.True(RuleBasedCategorizer.Matches("JMP S.A. BIEDRONKA", "biedronka"));
    }

    [Fact]
    public void Matches_is_case_insensitive_in_cyrillic_too()
    {
        // Monobank's ATM descriptor is what the seeded "банкомат" rule has to catch, and the
        // bank capitalises it. An ASCII-only case fold would let every withdrawal through.
        Assert.True(RuleBasedCategorizer.Matches("Банкомат 1616000011", "банкомат"));
        Assert.True(RuleBasedCategorizer.Matches("Зняття готівки: банкомат", "зняття готівки"));
        Assert.False(RuleBasedCategorizer.Matches("Банкоматний сервіс", "банкомат"));
    }

    [Fact]
    public void Matches_finds_later_occurrence_when_first_is_glued()
    {
        // first "zus" is glued (no match), second is a real word → true
        Assert.True(RuleBasedCategorizer.Matches("XZUSY then ZUS", "zus"));
    }
}
