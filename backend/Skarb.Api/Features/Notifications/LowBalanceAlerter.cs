using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Infrastructure.Notifications;

namespace Skarb.Api.Features.Notifications;

/// <summary>What a check decided for one account — see <see cref="LowBalanceAlerter.Evaluate"/>.</summary>
public enum LowBalanceCall
{
    None,
    /// <summary>The balance just crossed below the threshold — announce it.</summary>
    Send,
    /// <summary>Still below a day after the last message — nudge again so one missed ping can't strand the account.</summary>
    Remind,
    /// <summary>The balance recovered — clear the latch so the next drop is announced again.</summary>
    Rearm,
}

/// <summary>
/// Singleton, like <see cref="Features.Sync.SyncService"/>: sync rounds, webhooks and
/// settings edits all trigger checks, and the gate keeps two concurrent checks from both
/// seeing an un-set latch and double-sending.
/// </summary>
public class LowBalanceAlerter(
    IServiceScopeFactory scopeFactory,
    TelegramApiClient telegram,
    ILogger<LowBalanceAlerter> logger) : ILowBalanceAlerter
{
    /// <summary>How long a low balance may sit quiet before it is mentioned again.</summary>
    public static readonly TimeSpan RemindAfter = TimeSpan.FromHours(24);

    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task CheckAsync(CancellationToken ct)
    {
        await _gate.WaitAsync(ct);
        try
        {
            await RunAsync(ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Low-balance check failed");
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>
    /// The whole alerting policy, kept pure: alert on crossing below the threshold, stay
    /// quiet while the latch is fresh, remind daily while still below, re-arm on recovery.
    /// A balance exactly at the threshold counts as fine — the alert is for "less than".
    /// </summary>
    public static LowBalanceCall Evaluate(decimal? threshold, decimal balance, DateTime? notifiedAt, DateTime nowUtc)
    {
        if (threshold is not decimal limit) return LowBalanceCall.None;
        if (balance >= limit) return notifiedAt is null ? LowBalanceCall.None : LowBalanceCall.Rearm;
        if (notifiedAt is not DateTime last) return LowBalanceCall.Send;
        return nowUtc - last >= RemindAfter ? LowBalanceCall.Remind : LowBalanceCall.None;
    }

    public static string FormatMessage(Account a, bool reminder)
    {
        var name = string.IsNullOrEmpty(a.Bank) ? a.Name : $"{a.Bank} · {a.Name}";
        var balance = $"{Fmt(a.Balance)} {a.Currency}";
        var limit = $"{Fmt(a.LowBalanceThreshold!.Value)} {a.Currency}";
        return reminder
            ? $"⚠️ {name} is still low: {balance} (limit {limit})."
            : $"⚠️ {name} is down to {balance} — below the {limit} limit. Time to top it up.";
    }

    private static string Fmt(decimal amount) => amount.ToString("#,0.##", CultureInfo.InvariantCulture);

    private async Task RunAsync(CancellationToken ct)
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SkarbDbContext>();

        // Archived accounts stop syncing, so their stale balance says nothing worth alerting on.
        // Excluded ("don't count") accounts stay in: money someone else tops up is the main case.
        var accounts = await db.Accounts
            .Where(a => a.LowBalanceThreshold != null && !a.IsArchived)
            .ToListAsync(ct);
        if (accounts.Count == 0) return;

        var settings = await db.NotificationSettings.AsNoTracking().FirstOrDefaultAsync(ct)
            ?? new NotificationSettings();
        var now = DateTime.UtcNow;
        var dirty = false;

        foreach (var account in accounts)
        {
            var call = Evaluate(account.LowBalanceThreshold, account.Balance, account.LowBalanceNotifiedAt, now);
            if (call == LowBalanceCall.None) continue;

            if (call == LowBalanceCall.Rearm)
            {
                account.LowBalanceNotifiedAt = null;
                dirty = true;
                continue;
            }

            var chatId = account.LowBalanceChatId ?? settings.TelegramChatId;
            if (string.IsNullOrWhiteSpace(settings.TelegramBotToken) || string.IsNullOrWhiteSpace(chatId))
            {
                logger.LogWarning(
                    "{Account} is below its low-balance threshold but Telegram is not configured — no alert sent",
                    account.Name);
                continue;
            }

            try
            {
                await telegram.SendMessageAsync(settings.TelegramBotToken, chatId,
                    FormatMessage(account, reminder: call == LowBalanceCall.Remind), ct);
                account.LowBalanceNotifiedAt = now;
                db.SyncLogs.Add(new SyncLog
                {
                    Provider = "telegram",
                    Message = $"Low-balance alert sent for {account.Name}: " +
                              $"{Fmt(account.Balance)} {account.Currency} < {Fmt(account.LowBalanceThreshold!.Value)} {account.Currency}",
                });
            }
            catch (Exception ex)
            {
                // The latch stays unset, so the next balance change or sync round retries.
                logger.LogError(ex, "Low-balance alert for {Account} failed", account.Name);
                db.SyncLogs.Add(new SyncLog
                {
                    Provider = "telegram",
                    Message = $"Low-balance alert for {account.Name} failed: {ex.Message}",
                    Success = false,
                });
            }
            dirty = true;
        }

        if (dirty) await db.SaveChangesAsync(ct);
    }
}
