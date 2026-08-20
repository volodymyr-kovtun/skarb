using Skarb.Api.Common.Services;

namespace Skarb.Api.Tests;

/// <summary>
/// The keyword offered when a manual category change is turned into a rule. Descriptors here are
/// the real ones from <see cref="PkoDescriptorTests"/>, already cleaned by the provider, plus the
/// Polish shapes that motivated the trimming.
/// </summary>
public class MerchantKeywordTests
{
    private const string Card = "CARD-PAYMENT";

    private static string? Keyword(string description, string? typeCode = Card, string? counterParty = null) =>
        MerchantKeyword.For(description, counterParty, null, typeCode).Keyword;

    [Theory]
    [InlineData("JMP S.A. BIEDRONKA 7184", "biedronka")]        // holding company + till number
    [InlineData("PIEKARNIA BAKER'S HOUSE", "baker's house")]    // leading trade word
    [InlineData("ANTHROPIC* CLAUDE SUB", "anthropic")]          // cut at the processor's star
    [InlineData("DIGITALOCEAN.COM", "digitalocean.com")]        // already a key
    [InlineData("FOUNDATIONCOFFEE.PL", "foundationcoffee.pl")]
    [InlineData("ORLEN S.A.", "orlen")]                         // trailing company form
    [InlineData("APTEKA GEMINI 12", "gemini")]                  // trade word and till number
    [InlineData("Zabka Z7411", "zabka z7411")]                  // mixed token is not a till number
    public void Derives_a_merchant_key_from_the_descriptor(string descriptor, string expected)
    {
        Assert.Equal(expected, Keyword(descriptor));
    }

    [Theory]
    [InlineData("PRZELEW NA RACHUNEK", "TRANSFER-OUT")]
    [InlineData("PLATNOSC BLIK", "MOBILE-PAYMENT")]
    [InlineData("00043484974348496154042383313311", "TRANSFER-IN")]
    [InlineData("", Card)]
    public void Offers_nothing_when_the_descriptor_names_no_one(string descriptor, string typeCode)
    {
        Assert.Null(Keyword(descriptor, typeCode));
    }

    [Fact]
    public void Prefers_the_counterparty_when_the_bank_names_one()
    {
        // A transfer's description is boilerplate; the party is in its own field.
        Assert.Equal("urząd skarbowy", Keyword("PRZELEW NA RACHUNEK", "TRANSFER-OUT", "URZĄD SKARBOWY"));
    }

    [Fact]
    public void Offers_the_trimmings_back_as_alternatives()
    {
        var suggestion = MerchantKeyword.For("PIEKARNIA BAKER'S HOUSE", null, null, Card);
        Assert.Equal("baker's house", suggestion.Keyword);
        Assert.Contains("piekarnia baker's house", suggestion.Alternatives);
        Assert.Contains("piekarnia", suggestion.Alternatives);
    }

    [Fact]
    public void Never_offers_a_keyword_that_misses_its_own_transaction()
    {
        // The invariant that catches every derivation bug: whatever comes out has to fire on the
        // row it came from, under the same matcher that will run at ingest.
        string[] descriptors =
        [
            "JMP S.A. BIEDRONKA 7184", "PIEKARNIA BAKER'S HOUSE", "ANTHROPIC* CLAUDE SUB",
            "ORLEN S.A.", "DIGITALOCEAN.COM", "- mesGymBeam", "APTEKA GEMINI 12",
            "MIA CONSULTZUSA SP Z O.O.", "WSPÓLNOTA MIESZKANIOWA UL. DŁUGA 5",
        ];
        foreach (var descriptor in descriptors)
        {
            foreach (var typeCode in new[] { Card, "TRANSFER-OUT" })
            {
                var suggestion = MerchantKeyword.For(descriptor, null, null, typeCode);
                var haystack = RuleBasedCategorizer.Haystack(descriptor, null, null, typeCode);
                foreach (var candidate in new[] { suggestion.Keyword }.Concat(suggestion.Alternatives))
                {
                    if (candidate is null) continue;
                    Assert.True(RuleBasedCategorizer.RuleHits(haystack, typeCode, candidate),
                        $"'{candidate}' does not match its own source '{descriptor}' ({typeCode})");
                }
            }
        }
    }

    [Fact]
    public void Keeps_a_transfer_keyword_matchable_on_word_boundaries()
    {
        // Transfers use whole-word matching, so a keyword derived from one must not depend on
        // the substring fallback that only card rows get.
        var suggestion = MerchantKeyword.For("PRZELEW", "WSPÓLNOTA MIESZKANIOWA", null, "TRANSFER-OUT");
        Assert.Equal("wspólnota mieszkaniowa", suggestion.Keyword);
        Assert.True(RuleBasedCategorizer.Matches("PRZELEW WSPÓLNOTA MIESZKANIOWA TRANSFER-OUT", suggestion.Keyword!));
    }
}
