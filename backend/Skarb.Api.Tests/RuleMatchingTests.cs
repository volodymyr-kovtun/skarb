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
    public void Matches_is_case_insensitive()
    {
        Assert.True(RuleBasedCategorizer.Matches("biedronka 7184", "BIEDRONKA"));
        Assert.True(RuleBasedCategorizer.Matches("JMP S.A. BIEDRONKA", "biedronka"));
    }

    [Fact]
    public void Matches_finds_later_occurrence_when_first_is_glued()
    {
        // first "zus" is glued (no match), second is a real word → true
        Assert.True(RuleBasedCategorizer.Matches("XZUSY then ZUS", "zus"));
    }
}
