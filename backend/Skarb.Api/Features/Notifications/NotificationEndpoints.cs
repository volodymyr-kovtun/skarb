using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Infrastructure.Notifications;

namespace Skarb.Api.Features.Notifications;

/// <param name="BotToken">Null = keep the stored token; empty = disconnect the bot; otherwise validated and stored.</param>
/// <param name="ChatId">Null = keep the stored default chat.</param>
public record SaveTelegramRequest(string? BotToken, string? ChatId);

public class NotificationEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/notifications/telegram");

        // The token is write-only, like bank tokens: the UI only learns that one is stored.
        group.MapGet("/", async (SkarbDbContext db) =>
        {
            var s = await db.NotificationSettings.AsNoTracking().FirstOrDefaultAsync() ?? new NotificationSettings();
            return new
            {
                hasToken = !string.IsNullOrWhiteSpace(s.TelegramBotToken),
                botUsername = s.TelegramBotUsername,
                chatId = s.TelegramChatId,
            };
        });

        group.MapPatch("/", async (SaveTelegramRequest req, SkarbDbContext db,
            TelegramApiClient telegram, ILowBalanceAlerter alerter, CancellationToken ct) =>
        {
            var s = await db.NotificationSettings.FirstOrDefaultAsync(ct);
            if (s is null)
            {
                s = new NotificationSettings();
                db.NotificationSettings.Add(s);
            }

            if (req.BotToken is not null)
            {
                var token = req.BotToken.Trim();
                // getMe both proves the token works and captures the bot's name for the UI —
                // "message @skarb_bot" beats "message your bot".
                s.TelegramBotUsername = token.Length == 0 ? null : await telegram.GetBotUsernameAsync(token, ct);
                s.TelegramBotToken = token;
            }
            if (req.ChatId is not null) s.TelegramChatId = req.ChatId.Trim();
            s.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);

            // A just-configured bot may have alerts waiting — an account can already sit below
            // its threshold. Flush them now instead of at the next sync round.
            _ = Task.Run(() => alerter.CheckAsync(CancellationToken.None), CancellationToken.None);

            return Results.Ok(new
            {
                hasToken = !string.IsNullOrWhiteSpace(s.TelegramBotToken),
                botUsername = s.TelegramBotUsername,
                chatId = s.TelegramChatId,
            });
        });

        group.MapPost("/test", async (SaveTelegramRequest req, SkarbDbContext db,
            TelegramApiClient telegram, CancellationToken ct) =>
        {
            var s = await db.NotificationSettings.AsNoTracking().FirstOrDefaultAsync(ct) ?? new NotificationSettings();
            var chatId = string.IsNullOrWhiteSpace(req.ChatId) ? s.TelegramChatId : req.ChatId.Trim();
            if (string.IsNullOrWhiteSpace(chatId))
                throw new InvalidOperationException("No chat id to send to — set a default chat or pass one.");

            await telegram.SendMessageAsync(s.TelegramBotToken, chatId,
                "✅ Skarb can reach this chat. Low-balance alerts will arrive here.", ct);
            return Results.Ok(new { sentTo = chatId });
        });

        // Who has talked to the bot lately — lets the user pick a chat instead of finding its id.
        group.MapGet("/chats", async (SkarbDbContext db, TelegramApiClient telegram, CancellationToken ct) =>
        {
            var s = await db.NotificationSettings.AsNoTracking().FirstOrDefaultAsync(ct) ?? new NotificationSettings();
            return await telegram.GetRecentChatsAsync(s.TelegramBotToken, ct);
        });
    }
}
