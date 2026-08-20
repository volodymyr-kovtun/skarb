using System.Text.Json;

namespace Skarb.Api.Infrastructure.Notifications;

/// <summary>A chat the bot has seen recently — offered in the UI so nobody has to hunt for a numeric chat id.</summary>
public sealed record TelegramChat(string Id, string Name);

/// <summary>
/// Thin HTTP wrapper for the Telegram Bot API (https://core.telegram.org/bots/api):
/// URL building, JSON parsing, one error shape. No domain logic here.
/// </summary>
public class TelegramApiClient(IHttpClientFactory httpFactory)
{
    private const string BaseUrl = "https://api.telegram.org";

    /// <summary>Validates the token and returns the bot's @username.</summary>
    public async Task<string> GetBotUsernameAsync(string botToken, CancellationToken ct)
    {
        using var doc = await CallAsync(botToken, "getMe", null, ct);
        return doc.RootElement.GetProperty("result").GetProperty("username").GetString() ?? "";
    }

    public async Task SendMessageAsync(string botToken, string chatId, string text, CancellationToken ct)
    {
        using var _ = await CallAsync(botToken, "sendMessage", new { chat_id = chatId, text }, ct);
    }

    /// <summary>
    /// Chats that messaged the bot within Telegram's ~24h update window, oldest first.
    /// A bot cannot start a conversation, so the recipient opening the bot and pressing
    /// Start is what makes their chat appear here.
    /// </summary>
    public async Task<List<TelegramChat>> GetRecentChatsAsync(string botToken, CancellationToken ct)
    {
        using var doc = await CallAsync(botToken, "getUpdates", null, ct);
        var chats = new Dictionary<string, TelegramChat>();
        foreach (var update in doc.RootElement.GetProperty("result").EnumerateArray())
        {
            foreach (var kind in (string[])["message", "my_chat_member"])
            {
                if (!update.TryGetProperty(kind, out var payload) ||
                    !payload.TryGetProperty("chat", out var chat)) continue;
                var id = chat.GetProperty("id").GetRawText();
                chats[id] = new TelegramChat(id, DescribeChat(chat));
            }
        }
        return [.. chats.Values];
    }

    private static string DescribeChat(JsonElement chat)
    {
        string? Str(string name) => chat.TryGetProperty(name, out var v) ? v.GetString() : null;
        var name = Str("title") ?? $"{Str("first_name")} {Str("last_name")}".Trim();
        var username = Str("username");
        if (username is not null) name = name.Length > 0 ? $"{name} (@{username})" : $"@{username}";
        return name.Length > 0 ? name : "Unnamed chat";
    }

    /// <remarks>
    /// Telegram reports failures both ways at once — a non-2xx status and an
    /// <c>ok: false</c> body carrying a human-readable <c>description</c>. That
    /// description ("chat not found", "bot token is invalid") is exactly what the
    /// user needs to see, so it becomes the InvalidOperationException message.
    /// </remarks>
    private async Task<JsonDocument> CallAsync(string botToken, string method, object? payload, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(botToken))
            throw new InvalidOperationException("Telegram bot token is not configured. Add it in Settings → Notifications.");

        var http = httpFactory.CreateClient("telegram");
        http.BaseAddress = new Uri(BaseUrl);
        var url = $"/bot{botToken}/{method}";
        using var resp = payload is null
            ? await http.GetAsync(url, ct)
            : await http.PostAsJsonAsync(url, payload, ct);

        var body = await resp.Content.ReadAsStringAsync(ct);
        var doc = JsonDocument.Parse(body);
        if (resp.IsSuccessStatusCode &&
            doc.RootElement.TryGetProperty("ok", out var ok) && ok.GetBoolean())
            return doc;

        using (doc)
        {
            var description = doc.RootElement.TryGetProperty("description", out var d)
                ? d.GetString() : null;
            throw new InvalidOperationException($"Telegram {method} failed: {description ?? $"{(int)resp.StatusCode}"}");
        }
    }
}
