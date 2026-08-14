using System.Text.Json;
using Skarb.Api.Common.Abstractions;

namespace Skarb.Api.Infrastructure.Fx;

/// <summary>
/// IExchangeRateService backed by open.er-api.com (no API key), cached for 12 hours
/// with a static fallback when offline.
/// </summary>
public class OpenErApiExchangeRateService(IHttpClientFactory httpFactory, ILogger<OpenErApiExchangeRateService> logger)
    : IExchangeRateService
{
    private Dictionary<string, decimal> _rates = Fallback;
    private DateTime _fetchedAt = DateTime.MinValue;
    private readonly SemaphoreSlim _lock = new(1, 1);

    // Units of currency per 1 PLN (approximate fallback, refreshed from the API at runtime).
    private static readonly Dictionary<string, decimal> Fallback = new(StringComparer.OrdinalIgnoreCase)
    {
        ["PLN"] = 1m, ["UAH"] = 11.4m, ["EUR"] = 0.234m, ["USD"] = 0.274m,
        ["GBP"] = 0.202m, ["CZK"] = 5.7m, ["CHF"] = 0.218m,
    };

    public string BaseCurrency => "PLN";

    public async Task<decimal> ToBaseAsync(decimal amount, string currency, CancellationToken ct = default)
    {
        if (string.Equals(currency, BaseCurrency, StringComparison.OrdinalIgnoreCase)) return amount;
        var rates = await GetRatesAsync(ct);
        return rates.TryGetValue(currency, out var perPln) && perPln != 0
            ? Math.Round(amount / perPln, 2)
            : amount;
    }

    private async Task<Dictionary<string, decimal>> GetRatesAsync(CancellationToken ct)
    {
        if (DateTime.UtcNow - _fetchedAt < TimeSpan.FromHours(12)) return _rates;
        await _lock.WaitAsync(ct);
        try
        {
            if (DateTime.UtcNow - _fetchedAt < TimeSpan.FromHours(12)) return _rates;
            var http = httpFactory.CreateClient("rates");
            using var resp = await http.GetAsync("https://open.er-api.com/v6/latest/PLN", ct);
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
            _fetchedAt = DateTime.UtcNow - TimeSpan.FromHours(11); // retry in ~1h
        }
        finally
        {
            _lock.Release();
        }
        return _rates;
    }
}
