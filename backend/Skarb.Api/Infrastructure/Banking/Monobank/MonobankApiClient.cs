using System.Text.Json;
using System.Text.Json.Serialization;

namespace Skarb.Api.Infrastructure.Banking.Monobank;

public class MonobankSettings
{
    [JsonPropertyName("token")] public string Token { get; set; } = "";
}

/// <summary>
/// Thin HTTP wrapper for the Monobank personal API (https://api.monobank.ua):
/// auth header, 429 backoff, JSON parsing. No domain logic here.
/// </summary>
public class MonobankApiClient(IHttpClientFactory httpFactory, ILogger<MonobankApiClient> logger)
{
    private const string BaseUrl = "https://api.monobank.ua";

    public static readonly Dictionary<int, string> Iso4217 = new()
    {
        [980] = "UAH", [985] = "PLN", [978] = "EUR", [840] = "USD",
        [826] = "GBP", [203] = "CZK", [756] = "CHF", [348] = "HUF",
        [392] = "JPY", [124] = "CAD", [752] = "SEK", [578] = "NOK",
    };

    public Task<JsonDocument> GetClientInfoAsync(string token, CancellationToken ct) =>
        GetJsonAsync(token, "/personal/client-info", ct);

    public Task<JsonDocument> GetStatementAsync(string token, string accountId, long fromUnix, long toUnix, CancellationToken ct) =>
        GetJsonAsync(token, $"/personal/statement/{accountId}/{fromUnix}/{toUnix}", ct);

    public async Task SetWebhookAsync(string token, string webhookUrl, CancellationToken ct)
    {
        var http = CreateClient(token);
        var resp = await http.PostAsJsonAsync("/personal/webhook", new { webHookUrl = webhookUrl }, ct);
        if (!resp.IsSuccessStatusCode)
            throw new InvalidOperationException(
                $"Monobank webhook setup failed: {resp.StatusCode} {await resp.Content.ReadAsStringAsync(ct)}");
    }

    private HttpClient CreateClient(string token)
    {
        var http = httpFactory.CreateClient("monobank");
        http.BaseAddress = new Uri(BaseUrl);
        http.DefaultRequestHeaders.Remove("X-Token");
        http.DefaultRequestHeaders.Add("X-Token", token);
        return http;
    }

    private async Task<JsonDocument> GetJsonAsync(string token, string path, CancellationToken ct)
    {
        var http = CreateClient(token);
        using var resp = await http.GetAsync(path, ct);
        var body = await resp.Content.ReadAsStringAsync(ct);
        if (resp.StatusCode == System.Net.HttpStatusCode.TooManyRequests)
        {
            logger.LogWarning("Monobank 429 on {Path}, waiting 65s", path);
            await Task.Delay(TimeSpan.FromSeconds(65), ct);
            return await GetJsonAsync(token, path, ct);
        }
        if (!resp.IsSuccessStatusCode)
            throw new InvalidOperationException($"Monobank {path} failed: {(int)resp.StatusCode} {body}");
        return JsonDocument.Parse(body);
    }
}
