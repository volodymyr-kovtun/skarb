using System.Text.Json;
using Microsoft.Extensions.Options;
using Skarb.Api.Common.Abstractions;

namespace Skarb.Api.Infrastructure.Fx;

/// <summary>
/// IExchangeRateService backed by open.er-api.com (no API key), cached per
/// FxOptions.CacheHours with a static fallback when offline. One rate table is
/// fetched (units per 1 base currency), so any pair converts through the base.
/// </summary>
public class OpenErApiExchangeRateService(
    IHttpClientFactory httpFactory,
    IOptions<FxOptions> options,
    ILogger<OpenErApiExchangeRateService> logger) : IExchangeRateService
{
    private Dictionary<string, decimal> _rates = Fallback;
    private DateTime _fetchedAt = DateTime.MinValue;
    private readonly SemaphoreSlim _lock = new(1, 1);
    // Clamped because TimeSpan.FromHours overflows on a large enough typo, which would take
    // the service down at construction. Zero still means "refetch on every lookup".
    private readonly TimeSpan _cacheFor = TimeSpan.FromHours(Math.Clamp(options.Value.CacheHours, 0, 24 * 30));

    // Units of currency per 1 PLN (approximate fallback, refreshed from the API at runtime;
    // only meaningful while BaseCurrency is PLN — other bases rely on the live fetch).
    private static readonly Dictionary<string, decimal> Fallback = new(StringComparer.OrdinalIgnoreCase)
    {
        ["PLN"] = 1m, ["UAH"] = 11.4m, ["EUR"] = 0.234m, ["USD"] = 0.274m,
        ["GBP"] = 0.202m, ["CZK"] = 5.7m, ["CHF"] = 0.218m,
    };

    public string BaseCurrency => options.Value.BaseCurrency;

    public async Task<decimal> ConvertAsync(decimal amount, string from, string to, CancellationToken ct = default)
    {
        if (string.Equals(from, to, StringComparison.OrdinalIgnoreCase)) return amount;
        var rates = await GetRatesAsync(ct);
        if (!TryRate(rates, from, out var perBaseFrom) || !TryRate(rates, to, out var perBaseTo)) return amount;
        return Math.Round(amount / perBaseFrom * perBaseTo, 2);
    }

    public async Task<bool> IsKnownAsync(string currency, CancellationToken ct = default) =>
        TryRate(await GetRatesAsync(ct), currency, out _);

    /// <summary>
    /// Units of <paramref name="currency"/> per 1 base currency. The base itself is 1 even when
    /// the table omits it, which is what keeps a non-PLN base working on the fallback rates.
    /// </summary>
    private bool TryRate(Dictionary<string, decimal> rates, string currency, out decimal perBase)
    {
        if (string.Equals(currency, BaseCurrency, StringComparison.OrdinalIgnoreCase))
        {
            perBase = 1m;
            return true;
        }
        return rates.TryGetValue(currency, out perBase) && perBase != 0;
    }

    private async Task<Dictionary<string, decimal>> GetRatesAsync(CancellationToken ct)
    {
        if (DateTime.UtcNow - _fetchedAt < _cacheFor) return _rates;
        await _lock.WaitAsync(ct);
        try
        {
            if (DateTime.UtcNow - _fetchedAt < _cacheFor) return _rates;
            var http = httpFactory.CreateClient("rates");
            using var resp = await http.GetAsync($"https://open.er-api.com/v6/latest/{BaseCurrency}", ct);
            resp.EnsureSuccessStatusCode();
            using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync(ct));
            var parsed = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
            foreach (var p in doc.RootElement.GetProperty("rates").EnumerateObject())
                parsed[p.Name] = p.Value.GetDecimal();
            if (parsed.Count > 0)
            {
                _rates = parsed;
                _fetchedAt = DateTime.UtcNow;
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Exchange rate refresh failed, using cached/fallback rates");
            _fetchedAt = DateTime.UtcNow - _cacheFor + TimeSpan.FromHours(1); // retry in ~1h
        }
        finally
        {
            _lock.Release();
        }
        return _rates;
    }
}
