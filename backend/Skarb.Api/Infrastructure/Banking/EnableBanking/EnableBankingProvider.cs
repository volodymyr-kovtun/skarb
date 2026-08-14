using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Infrastructure.Banking.EnableBanking;

/// <summary>
/// IBankProvider for Enable Banking (PKO BP and 2,500+ other European banks).
/// Free for personal use in "restricted production" mode (your own linked accounts).
/// </summary>
public class EnableBankingProvider(
    SkarbDbContext db,
    EnableBankingApiClient api,
    ITransactionIngestor ingestor,
    IOptions<SyncOptions> options,
    ILogger<EnableBankingProvider> logger) : IBankProvider
{
    public string Key => ProviderNames.EnableBanking;

    public async Task<SyncResult> SyncAsync(BankConnection connection, CancellationToken ct)
    {
        var settings = EnableBankingSettings.From(connection);
        if (string.IsNullOrWhiteSpace(settings.SessionId))
            throw new InvalidOperationException(
                "Bank authorization has not been completed yet. Open Settings and finish linking the bank.");

        var accounts = await db.Accounts
            .Where(a => a.ConnectionId == connection.Id && !a.IsArchived)
            .ToListAsync(ct);

        var newTx = 0;
        foreach (var account in accounts)
        {
            await RefreshBalanceAsync(settings, account, ct);
            newTx += await FetchTransactionsAsync(settings, account, ct);
        }

        await db.SaveChangesAsync(ct);
        return new SyncResult(newTx);
    }

    /// <summary>Exchanges the authorization code for a session and upserts the linked bank accounts.</summary>
    public async Task CompleteAuthAsync(BankConnection connection, string code, CancellationToken ct)
    {
        var settings = EnableBankingSettings.From(connection);
        using var doc = await api.CreateSessionAsync(settings, code, ct);

        settings.SessionId = doc.RootElement.GetProperty("session_id").GetString();
        if (doc.RootElement.TryGetProperty("access", out var access) &&
            access.TryGetProperty("valid_until", out var vu) &&
            DateTime.TryParse(vu.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal, out var validUntil))
            settings.ValidUntil = DateTime.SpecifyKind(validUntil, DateTimeKind.Utc);

        foreach (var acc in doc.RootElement.GetProperty("accounts").EnumerateArray())
        {
            var uid = acc.GetProperty("uid").GetString()!;
            var account = await db.Accounts.FirstOrDefaultAsync(
                a => a.ConnectionId == connection.Id && a.ExternalId == uid, ct);
            var currency = acc.TryGetProperty("currency", out var cur) ? cur.GetString() ?? "PLN" : "PLN";
            var iban = acc.TryGetProperty("account_id", out var accId) && accId.ValueKind == JsonValueKind.Object &&
                       accId.TryGetProperty("iban", out var i) ? i.GetString() : null;
            var product = acc.TryGetProperty("product", out var p) ? p.GetString() : null;
            var name = acc.TryGetProperty("name", out var n) && !string.IsNullOrWhiteSpace(n.GetString())
                ? n.GetString()! : product ?? $"{connection.DisplayName} ({currency})";

            if (account is null)
            {
                account = new Account
                {
                    Name = name,
                    Bank = connection.DisplayName,
                    Provider = ProviderNames.EnableBanking,
                    ConnectionId = connection.Id,
                    ExternalId = uid,
                    Color = "#0B5FFF",
                };
                db.Accounts.Add(account);
            }

            account.Currency = currency;
            account.Iban = iban ?? account.Iban;
        }

        settings.SaveTo(connection);
        connection.Status = "linked";
        await db.SaveChangesAsync(ct);
    }

    private async Task RefreshBalanceAsync(EnableBankingSettings settings, Account account, CancellationToken ct)
    {
        try
        {
            using var balances = await api.GetBalancesAsync(settings, account.ExternalId!, ct);
            var first = balances.RootElement.GetProperty("balances").EnumerateArray().FirstOrDefault();
            if (first.ValueKind == JsonValueKind.Object)
            {
                var ba = first.GetProperty("balance_amount");
                account.Balance = decimal.Parse(ba.GetProperty("amount").GetString()!, CultureInfo.InvariantCulture);
                account.Currency = ba.GetProperty("currency").GetString() ?? account.Currency;
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Balance fetch failed for account {Account}", account.Name);
        }
    }

    private async Task<int> FetchTransactionsAsync(EnableBankingSettings settings, Account account, CancellationToken ct)
    {
        var lastKnown = await db.Transactions
            .Where(t => t.AccountId == account.Id && t.ExternalId != null)
            .MaxAsync(t => (DateTime?)t.OccurredAt, ct);
        var dateFrom = (lastKnown?.AddDays(-3) ?? DateTime.UtcNow.AddDays(-Math.Max(options.Value.InitialHistoryDays, 90)))
            .ToString("yyyy-MM-dd");

        var added = 0;
        string? continuationKey = null;
        do
        {
            using var doc = await api.GetTransactionsAsync(settings, account.ExternalId!, dateFrom, continuationKey, ct);
            var incoming = doc.RootElement.GetProperty("transactions").EnumerateArray()
                .Select(tx => MapTransaction(tx, account.Currency))
                .Where(tx => tx is not null)
                .Select(tx => tx!)
                .ToList();
            added += await ingestor.IngestAsync(account, incoming, ct);

            continuationKey = doc.RootElement.TryGetProperty("continuation_key", out var ck) &&
                              ck.ValueKind == JsonValueKind.String ? ck.GetString() : null;
        } while (continuationKey is not null);

        return added;
    }

    private static IncomingTransaction? MapTransaction(JsonElement tx, string accountCurrency)
    {
        var status = tx.TryGetProperty("status", out var st) ? st.GetString() : "BOOK";
        if (status == "PDNG") return null; // skip pending; they arrive again once booked

        var amountObj = tx.GetProperty("transaction_amount");
        var amount = decimal.Parse(amountObj.GetProperty("amount").GetString()!, CultureInfo.InvariantCulture);
        var indicator = tx.TryGetProperty("credit_debit_indicator", out var cdi) ? cdi.GetString() : "DBIT";
        amount = indicator == "DBIT" ? -Math.Abs(amount) : Math.Abs(amount);

        var remittance = tx.TryGetProperty("remittance_information", out var ri) && ri.ValueKind == JsonValueKind.Array
            ? string.Join(" ", ri.EnumerateArray().Select(x => x.GetString())) : "";
        var counterParty = PartyName(tx, amount < 0 ? "creditor" : "debtor");
        var counterIban = PartyIban(tx, amount < 0 ? "creditor_account" : "debtor_account");
        var description = !string.IsNullOrWhiteSpace(counterParty) ? counterParty! :
            !string.IsNullOrWhiteSpace(remittance) ? remittance : "Transaction";

        var dateStr = FirstString(tx, "booking_date", "transaction_date", "value_date");
        var occurredAt = DateTime.TryParse(dateStr, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal, out var dt)
            ? DateTime.SpecifyKind(dt, DateTimeKind.Utc) : DateTime.UtcNow;

        var externalId = tx.TryGetProperty("entry_reference", out var er) && er.ValueKind == JsonValueKind.String &&
                         !string.IsNullOrWhiteSpace(er.GetString())
            ? er.GetString()!
            : StableHash($"{occurredAt:yyyy-MM-dd}|{amount}|{description}|{remittance}");

        return new IncomingTransaction(
            externalId, amount,
            amountObj.GetProperty("currency").GetString() ?? accountCurrency,
            description, occurredAt, TransactionSources.Sync)
        {
            CounterParty = counterParty,
            CounterIban = counterIban,
            Note = string.IsNullOrWhiteSpace(remittance) || remittance == description ? null : remittance,
        };
    }

    private static string? PartyName(JsonElement tx, string prop) =>
        tx.TryGetProperty(prop, out var p) && p.ValueKind == JsonValueKind.Object &&
        p.TryGetProperty("name", out var n) ? n.GetString() : null;

    private static string? PartyIban(JsonElement tx, string prop) =>
        tx.TryGetProperty(prop, out var p) && p.ValueKind == JsonValueKind.Object &&
        p.TryGetProperty("iban", out var i) ? i.GetString() : null;

    private static string? FirstString(JsonElement tx, params string[] props)
    {
        foreach (var prop in props)
        {
            if (tx.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.String)
                return v.GetString();
        }
        return null;
    }

    private static string StableHash(string input)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(input));
        return "h_" + Convert.ToHexString(bytes)[..24].ToLowerInvariant();
    }
}
