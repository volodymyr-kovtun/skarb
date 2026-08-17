using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Infrastructure.Banking.Monobank;

/// <summary>
/// IBankProvider for Monobank. Respects the documented limits: 1 statement request
/// per 60s, 31-day window, 500 items per page (paginate by moving `to` down).
/// </summary>
public class MonobankProvider(
    SkarbDbContext db,
    MonobankApiClient api,
    ITransactionIngestor ingestor,
    IOptions<SyncOptions> options) : IBankProvider
{
    private const int StatementWindowSeconds = 2_682_000; // 31 days + 1 hour
    private static readonly TimeSpan RateLimitDelay = TimeSpan.FromSeconds(61);
    private DateTime _lastStatementAt = DateTime.MinValue;

    public string Key => ProviderNames.Monobank;

    /// <summary>Monobank amounts are int64 minor units (kopecks/cents).</summary>
    public static decimal FromMinor(long minor) => minor / 100m;

    /// <summary>The reported balance includes the credit limit; own funds is what users expect to see.</summary>
    public static decimal OwnFunds(long balanceMinor, decimal creditLimit) => FromMinor(balanceMinor) - creditLimit;

    public async Task<SyncResult> SyncAsync(BankConnection connection, CancellationToken ct)
    {
        var settings = MonobankSettings.From(connection);
        if (string.IsNullOrWhiteSpace(settings.Token))
            throw new InvalidOperationException("Monobank token is not configured.");

        var accounts = (await UpsertAccountsAsync(connection, settings.Token, ct))
            .Where(a => !a.IsArchived)
            .ToList();
        var watermarks = await db.LastSyncedByAccountAsync(accounts.Select(a => a.Id).ToList(), ct);

        var newTx = 0;
        foreach (var account in accounts)
        {
            var from = watermarks.TryGetValue(account.Id, out var last)
                ? last.AddHours(-2)
                : DateTime.UtcNow.AddDays(-options.Value.InitialHistoryDays);
            newTx += await FetchStatementsAsync(settings.Token, account, from, ct);
        }

        return new SyncResult(newTx);
    }

    private async Task<List<Account>> UpsertAccountsAsync(BankConnection connection, string token, CancellationToken ct)
    {
        using var clientInfo = await api.GetClientInfoAsync(token, ct);
        var existing = await db.Accounts
            .Where(a => a.ConnectionId == connection.Id && a.ExternalId != null)
            .ToDictionaryAsync(a => a.ExternalId!, ct);
        var accounts = new List<Account>();

        foreach (var acc in clientInfo.RootElement.GetProperty("accounts").EnumerateArray())
        {
            var externalId = acc.GetProperty("id").GetString()!;
            var currency = MonobankApiClient.Iso4217.GetValueOrDefault(acc.GetProperty("currencyCode").GetInt32(), "UAH");
            var creditLimit = acc.TryGetProperty("creditLimit", out var cl) ? FromMinor(cl.GetInt64()) : 0m;
            var type = acc.TryGetProperty("type", out var t) ? t.GetString() : "black";

            if (!existing.TryGetValue(externalId, out var account))
            {
                account = new Account
                {
                    Name = $"Monobank {type} ({currency})",
                    Bank = "Monobank",
                    Provider = ProviderNames.Monobank,
                    ConnectionId = connection.Id,
                    ExternalId = externalId,
                    Color = "#1A1A2E",
                };
                db.Accounts.Add(account);
                existing[externalId] = account;
            }

            account.Currency = currency;
            account.Balance = OwnFunds(acc.GetProperty("balance").GetInt64(), creditLimit);
            account.CreditLimit = creditLimit;
            account.MaskedPan = acc.TryGetProperty("maskedPan", out var mp) && mp.GetArrayLength() > 0
                ? mp[0].GetString() : account.MaskedPan;
            account.Iban = acc.TryGetProperty("iban", out var iban) ? iban.GetString() : account.Iban;
            accounts.Add(account);
        }

        await db.SaveChangesAsync(ct);
        return accounts;
    }

    private async Task<int> FetchStatementsAsync(string token, Account account, DateTime fromUtc, CancellationToken ct)
    {
        var added = 0;
        var windowStart = new DateTimeOffset(DateTime.SpecifyKind(fromUtc, DateTimeKind.Utc)).ToUnixTimeSeconds();
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        while (windowStart < now)
        {
            var windowEnd = Math.Min(windowStart + StatementWindowSeconds, now);

            // Paginate inside the window: max 500 items per response, newest first.
            var pageTo = windowEnd;
            while (true)
            {
                await ThrottleAsync(ct);
                using var doc = await api.GetStatementAsync(token, account.ExternalId!, windowStart, pageTo, ct);
                var items = doc.RootElement.EnumerateArray().ToList();

                added += await ingestor.IngestAsync(
                    account,
                    items.Select(i => MapStatementItem(i, account.Currency, TransactionSources.Sync)).ToList(),
                    ct);

                if (items.Count < 500) break;
                pageTo = items[^1].GetProperty("time").GetInt64() - 1;
            }

            windowStart = windowEnd;
        }

        return added;
    }

    /// <summary>Waits only the remainder of the 60s statement rate limit — the first request of a sync goes out immediately.</summary>
    private async Task ThrottleAsync(CancellationToken ct)
    {
        var wait = RateLimitDelay - (DateTime.UtcNow - _lastStatementAt);
        if (wait > TimeSpan.Zero) await Task.Delay(wait, ct);
        _lastStatementAt = DateTime.UtcNow;
    }

    /// <summary>Maps a Monobank statement item (statement or webhook payload) to the ingestion contract.</summary>
    public static IncomingTransaction MapStatementItem(JsonElement item, string accountCurrency, string source) => new(
        ExternalId: item.GetProperty("id").GetString()!,
        Amount: FromMinor(item.GetProperty("amount").GetInt64()),
        Currency: accountCurrency,
        Description: item.TryGetProperty("description", out var d) ? d.GetString() ?? "" : "",
        OccurredAtUtc: DateTimeOffset.FromUnixTimeSeconds(item.GetProperty("time").GetInt64()).UtcDateTime,
        Source: source)
    {
        CounterParty = item.TryGetProperty("counterName", out var cn) ? cn.GetString() : null,
        CounterIban = item.TryGetProperty("counterIban", out var ci) ? ci.GetString() : null,
        Mcc = item.TryGetProperty("mcc", out var m) ? m.GetInt32() : null,
        Note = item.TryGetProperty("comment", out var c) ? c.GetString() : null,
    };
}
