using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Infrastructure.Banking.EnableBanking;

public class EnableBankingSettings
{
    [JsonPropertyName("applicationId")] public string ApplicationId { get; set; } = "";
    [JsonPropertyName("privateKeyPem")] public string PrivateKeyPem { get; set; } = "";
    [JsonPropertyName("sessionId")] public string? SessionId { get; set; }
    [JsonPropertyName("aspspName")] public string? AspspName { get; set; }
    [JsonPropertyName("aspspCountry")] public string? AspspCountry { get; set; }
    [JsonPropertyName("validUntil")] public DateTime? ValidUntil { get; set; }

    public static EnableBankingSettings From(BankConnection c) =>
        JsonSerializer.Deserialize<EnableBankingSettings>(c.SettingsJson) ?? new();

    public void SaveTo(BankConnection c) => c.SettingsJson = JsonSerializer.Serialize(this);
}

/// <summary>
/// Thin HTTP wrapper for the Enable Banking API (https://api.enablebanking.com):
/// RS256 JWT auth signed with the application's RSA key, JSON in/out. No domain logic.
/// </summary>
public class EnableBankingApiClient(IHttpClientFactory httpFactory)
{
    private const string BaseUrl = "https://api.enablebanking.com";

    /// <summary>Lists banks; pass null country to get every supported institution.</summary>
    public Task<JsonDocument> GetAspspsAsync(EnableBankingSettings settings, string? country, CancellationToken ct) =>
        GetAsync(settings, country is null ? "/aspsps" : $"/aspsps?country={Uri.EscapeDataString(country)}", ct);

    public async Task<string> StartAuthAsync(EnableBankingSettings settings, string aspspName, string aspspCountry,
        string redirectUrl, string state, CancellationToken ct)
    {
        var body = new
        {
            access = new { valid_until = DateTime.UtcNow.AddDays(89).ToString("yyyy-MM-ddTHH:mm:ss.000000+00:00") },
            aspsp = new { name = aspspName, country = aspspCountry },
            state,
            redirect_url = redirectUrl,
            psu_type = "personal",
        };
        using var doc = await PostAsync(settings, "/auth", body, ct);
        return doc.RootElement.GetProperty("url").GetString()!;
    }

    public Task<JsonDocument> CreateSessionAsync(EnableBankingSettings settings, string code, CancellationToken ct) =>
        PostAsync(settings, "/sessions", new { code }, ct);

    public Task<JsonDocument> GetBalancesAsync(EnableBankingSettings settings, string accountUid, CancellationToken ct) =>
        GetAsync(settings, $"/accounts/{accountUid}/balances", ct);

    public Task<JsonDocument> GetTransactionsAsync(EnableBankingSettings settings, string accountUid,
        string dateFrom, string? continuationKey, CancellationToken ct) =>
        GetAsync(settings,
            $"/accounts/{accountUid}/transactions?date_from={dateFrom}" +
            (continuationKey is null ? "" : $"&continuation_key={Uri.EscapeDataString(continuationKey)}"), ct);

    private async Task<JsonDocument> GetAsync(EnableBankingSettings settings, string path, CancellationToken ct)
    {
        using var resp = await CreateClient(settings).GetAsync(path, ct);
        return await BankingHttp.ReadJsonAsync(resp, $"Enable Banking {path}", ct);
    }

    private async Task<JsonDocument> PostAsync(EnableBankingSettings settings, string path, object body, CancellationToken ct)
    {
        using var resp = await CreateClient(settings).PostAsJsonAsync(path, body, ct);
        return await BankingHttp.ReadJsonAsync(resp, $"Enable Banking {path}", ct);
    }

    private HttpClient CreateClient(EnableBankingSettings settings)
    {
        if (string.IsNullOrWhiteSpace(settings.ApplicationId) || string.IsNullOrWhiteSpace(settings.PrivateKeyPem))
            throw new InvalidOperationException("Enable Banking application id / private key are not configured.");
        var http = httpFactory.CreateClient("enablebanking");
        http.BaseAddress = new Uri(BaseUrl);
        http.DefaultRequestHeaders.Remove("Authorization");
        http.DefaultRequestHeaders.Add("Authorization", $"Bearer {GetJwt(settings)}");
        return http;
    }

    // JWTs are valid for an hour — signing one RSA token per HTTP request (each page of a
    // paginated fetch) is pure waste, so cache per application until shortly before expiry.
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, (string Jwt, DateTimeOffset ExpiresAt)> JwtCache = new();

    private static string GetJwt(EnableBankingSettings settings)
    {
        if (JwtCache.TryGetValue(settings.ApplicationId, out var cached) &&
            cached.ExpiresAt > DateTimeOffset.UtcNow.AddMinutes(5))
            return cached.Jwt;

        var jwt = CreateJwt(settings.ApplicationId, settings.PrivateKeyPem);
        JwtCache[settings.ApplicationId] = (jwt, DateTimeOffset.UtcNow.AddHours(1));
        return jwt;
    }

    /// <summary>RS256 JWT per Enable Banking docs: kid = application id, iss/aud fixed, 1h lifetime.</summary>
    internal static string CreateJwt(string applicationId, string privateKeyPem)
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var header = JsonSerializer.Serialize(new { typ = "JWT", alg = "RS256", kid = applicationId });
        var payload = JsonSerializer.Serialize(new
        {
            iss = "enablebanking.com",
            aud = "api.enablebanking.com",
            iat = now,
            exp = now + 3600,
        });

        var signingInput = $"{Base64Url(Encoding.UTF8.GetBytes(header))}.{Base64Url(Encoding.UTF8.GetBytes(payload))}";
        using var rsa = RSA.Create();
        rsa.ImportFromPem(privateKeyPem);
        var signature = rsa.SignData(Encoding.UTF8.GetBytes(signingInput), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        return $"{signingInput}.{Base64Url(signature)}";
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
