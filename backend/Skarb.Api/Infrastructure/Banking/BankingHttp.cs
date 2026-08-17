using System.Text.Json;

namespace Skarb.Api.Infrastructure.Banking;

internal static class BankingHttp
{
    /// <summary>Shared response handling for bank API clients: one error shape, one JSON parse.</summary>
    public static async Task<JsonDocument> ReadJsonAsync(HttpResponseMessage resp, string context, CancellationToken ct)
    {
        var body = await resp.Content.ReadAsStringAsync(ct);
        if (!resp.IsSuccessStatusCode)
            throw new InvalidOperationException($"{context} failed: {(int)resp.StatusCode} {body}");
        return JsonDocument.Parse(body);
    }
}
