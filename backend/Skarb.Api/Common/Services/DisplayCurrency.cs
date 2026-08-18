using Skarb.Api.Common.Abstractions;

namespace Skarb.Api.Common.Services;

/// <summary>
/// Which currency a reporting endpoint answers in, and what its switcher may offer.
/// Shared so the overview and the tag report never disagree about either.
/// </summary>
public static class DisplayCurrency
{
    /// <summary>Always offered, on top of the base currency and whatever the accounts are held in.</summary>
    private static readonly string[] AlwaysOffered = ["PLN", "EUR", "USD"];

    /// <summary>Unknown or missing input falls back to the base currency, so a stale bookmark still renders.</summary>
    public static async Task<string> ResolveAsync(IExchangeRateService fx, string? requested, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(requested)) return fx.BaseCurrency;
        var code = requested.Trim().ToUpperInvariant();
        return code.Length == 3 && await fx.IsKnownAsync(code, ct) ? code : fx.BaseCurrency;
    }

    /// <summary>Base first, then the currencies actually held, then the majors — codes with known rates only.</summary>
    public static async Task<List<string>> OptionsAsync(
        IExchangeRateService fx, IEnumerable<string> heldCurrencies, CancellationToken ct = default)
    {
        var codes = new List<string> { fx.BaseCurrency.ToUpperInvariant() };
        foreach (var raw in heldCurrencies.Concat(AlwaysOffered))
        {
            var code = raw.ToUpperInvariant();
            if (!codes.Contains(code) && await fx.IsKnownAsync(code, ct)) codes.Add(code);
        }
        return codes;
    }
}
