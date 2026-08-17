using System.Text.Json;
using System.Text.Json.Serialization;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Infrastructure.Banking.Monobank;

public class MonobankSettings
{
    [JsonPropertyName("token")] public string Token { get; set; } = "";

    public static MonobankSettings From(BankConnection c) =>
        JsonSerializer.Deserialize<MonobankSettings>(c.SettingsJson) ?? new();

    public void SaveTo(BankConnection c) => c.SettingsJson = JsonSerializer.Serialize(this);
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
        // Success response has an empty body — only the status matters here.
        using var resp = await CreateClient(token).PostAsJsonAsync("/personal/webhook", new { webHookUrl = webhookUrl }, ct);
        if (!resp.IsSuccessStatusCode)
            throw new InvalidOperationException(
                $"Monobank webhook setup failed: {(int)resp.StatusCode} {await resp.Content.ReadAsStringAsync(ct)}");
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
        using var resp = await CreateClient(token).GetAsync(path, ct);
        if (resp.StatusCode == System.Net.HttpStatusCode.TooManyRequests)
        {
            logger.LogWarning("Monobank 429 on {Path}, waiting 65s", path);
            await Task.Delay(TimeSpan.FromSeconds(65), ct);
            return await GetJsonAsync(token, path, ct);
        }
        return await BankingHttp.ReadJsonAsync(resp, $"Monobank {path}", ct);
    }
}
