using Skarb.Api.Infrastructure.Banking.EnableBanking;

namespace Skarb.Api.Tests;

/// <summary>
/// PKO (via Enable Banking) sends card rows as CITY+MERCHANT+COUNTRY glued together and a
/// trailing type code in remittance_information. These pin the cleanup behaviour.
/// </summary>
public class PkoDescriptorTests
{
    [Theory]
    [InlineData("CARD-PAYMENT", true)]
    [InlineData("MOBILE-PAYMENT-C2C", true)]
    [InlineData("FEE", true)]
    [InlineData("TRANSFER-IN", true)]
    [InlineData("CARD-PAYMENT-RETURN", true)]
    [InlineData("WARSZAWAJMP S.A. BIEDRONKA 7184PL", false)]   // has spaces/lowercase-ish content
    [InlineData("PRZELEW IKO NA NUMER RACHUNKU", false)]
    [InlineData("00043484974348496154042383313311", true)]      // digits-only passes shape check (caller requires ≥2 parts)
    [InlineData("AB", false)]                                    // too short
    public void LooksLikeTypeCode_recognises_bank_type_tokens(string value, bool expected)
    {
        Assert.Equal(expected, EnableBankingProvider.LooksLikeTypeCode(value));
    }

    [Theory]
    [InlineData("WARSZAWAJMP S.A. BIEDRONKA 7184PL", "CARD-PAYMENT", "JMP S.A. BIEDRONKA 7184")]
    [InlineData("WARSZAWAFOUNDATIONCOFFEE.PLPL", "CARD-PAYMENT", "FOUNDATIONCOFFEE.PL")]
    [InlineData("DUBLINANTHROPIC* CLAUDE SUBIE", "CARD-PAYMENT", "ANTHROPIC* CLAUDE SUB")]
    [InlineData("Koshice - mesGymBeamSK", "CARD-PAYMENT", "- mesGymBeam")]
    [InlineData("AMSTERDAMDIGITALOCEAN.COMNL", "CARD-PAYMENT", "DIGITALOCEAN.COM")]
    public void CleanCardMerchant_strips_city_prefix_and_country_suffix(string raw, string typeCode, string expected)
    {
        Assert.Equal(expected, EnableBankingProvider.CleanCardMerchant(raw, typeCode));
    }

    [Fact]
    public void CleanCardMerchant_leaves_non_card_rows_untouched()
    {
        const string transfer = "PRZELEW IKO NA NUMER RACHUNKU";
        Assert.Equal(transfer, EnableBankingProvider.CleanCardMerchant(transfer, "TRANSFER-IN"));
        Assert.Equal(transfer, EnableBankingProvider.CleanCardMerchant(transfer, null));
    }

    [Fact]
    public void CleanCardMerchant_keeps_company_suffixes_like_SA()
    {
        // "S.A." ends in '.', so the trailing-country strip must not touch it.
        Assert.Equal("ORLEN S.A.", EnableBankingProvider.CleanCardMerchant("ORLEN S.A.", "CARD-PAYMENT"));
    }
}
