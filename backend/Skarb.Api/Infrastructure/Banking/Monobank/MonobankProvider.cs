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

    public string Key => ProviderNames.Monobank;

    public async Task<SyncResult> SyncAsync(BankConnection connection, CancellationToken ct)
    {
        var settings = JsonSerializer.Deserialize<MonobankSettings>(connection.SettingsJson) ?? new();
        if (string.IsNullOrWhiteSpace(settings.Token))
            throw new InvalidOperationException("Monobank token is not configured.");

        var accounts = await UpsertAccountsAsync(connection, settings.Token, ct);

        var newTx = 0;
        foreach (var account in accounts.Where(a => !a.IsArchived))
        {
            var lastKnown = await db.Transactions
                .Where(t => t.AccountId == account.Id && t.ExternalId != null)
                .MaxAsync(t => (DateTime?)t.OccurredAt, ct);
            var from = lastKnown?.AddHours(-2) ?? DateTime.UtcNow.AddDays(-options.Value.InitialHistoryDays);
            newTx += await FetchStatementsAsync(settings.Token, account, from, ct);
        }

        return new SyncResult(newTx);
    }

    private async Task<List<Account>> UpsertAccountsAsync(BankConnection connection, string token, CancellationToken ct)
    {
        using var clientInfo = await api.GetClientInfoAsync(token, ct);
        var accounts = new List<Account>();

        foreach (var acc in clientInfo.RootElement.GetProperty("accounts").EnumerateArray())
        {
            var externalId = acc.GetProperty("id").GetString()!;
            var account = await db.Accounts.FirstOrDefaultAsync(
                a => a.ConnectionId == connection.Id && a.ExternalId == externalId, ct);
            var currency = MonobankApiClient.Iso4217.GetValueOrDefault(acc.GetProperty("currencyCode").GetInt32(), "UAH");
            var creditLimit = acc.TryGetProperty("creditLimit", out var cl) ? cl.GetInt64() / 100m : 0m;
            var type = acc.TryGetProperty("type", out var t) ? t.GetString() : "black";

            if (account is null)
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
            }

            account.Currency = currency;
            account.Balance = acc.GetProperty("balance").GetInt64() / 100m - creditLimit; // own funds
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
                await Task.Delay(RateLimitDelay, ct); // 1 statement request per 60s
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

    /// <summary>Maps a Monobank statement item (statement or webhook payload) to the ingestion contract.</summary>
    public static IncomingTransaction MapStatementItem(JsonElement item, string accountCurrency, string source) => new(
        ExternalId: item.GetProperty("id").GetString()!,
        Amount: item.GetProperty("amount").GetInt64() / 100m,
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
