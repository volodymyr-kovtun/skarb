using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Features.Accounts;

/// <param name="IsCash">
/// A cash wallet rather than an ordinary manual account. Name and bank are then Skarb's to
/// choose — a wallet is identified by its currency, and there is only ever one per currency.
/// </param>
public record CreateAccountRequest(
    string? Name, string? Bank, string Currency, decimal Balance, string? Color, bool IsCash = false);
/// <param name="LowBalanceSet">Distinguishes "leave the alert alone" from "turn it off" (null threshold), like CategorySet on transactions.</param>
public record UpdateAccountRequest(
    string? Name, string? Color, bool? IsArchived, bool? IsExcluded,
    bool LowBalanceSet = false, decimal? LowBalanceThreshold = null, string? LowBalanceChatId = null,
    bool? IsCash = null);

public class AccountEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/accounts");

        group.MapPost("/", async (CreateAccountRequest req, SkarbDbContext db) =>
        {
            var currency = (req.Currency ?? "").Trim().ToUpperInvariant();
            if (currency.Length != 3) return Results.BadRequest(new { error = "Currency must be a three-letter code, like EUR." });

            Account account;
            if (req.IsCash)
            {
                if (await WalletExistsAsync(db, currency, except: null))
                    return Results.BadRequest(new { error = DuplicateWallet(currency) });
                account = CashWallet.New(currency);
            }
            else
            {
                if (string.IsNullOrWhiteSpace(req.Name)) return Results.BadRequest(new { error = "Give the account a name." });
                account = new Account
                {
                    Name = req.Name.Trim(),
                    Bank = string.IsNullOrWhiteSpace(req.Bank) ? "Manual" : req.Bank,
                    Provider = ProviderNames.Manual,
                    Currency = currency,
                };
            }
            account.Balance = req.Balance;
            if (req.Color is not null) account.Color = req.Color;
            db.Accounts.Add(account);
            if (req.Balance != 0)
            {
                db.Transactions.Add(new Transaction
                {
                    AccountId = account.Id,
                    Amount = req.Balance,
                    Currency = account.Currency,
                    Description = "Opening balance",
                    OccurredAt = DateTime.UtcNow,
                    Source = TransactionSources.Manual,
                    IsExcluded = true,
                });
            }
            await db.SaveChangesAsync();
            return Results.Created($"/api/accounts/{account.Id}", account.ToDto());
        });

        group.MapPatch("/{id:guid}", async (Guid id, UpdateAccountRequest req, SkarbDbContext db, ILowBalanceAlerter alerter) =>
        {
            var account = await db.Accounts.FindAsync(id);
            if (account is null) return Results.NotFound();
            if (req.IsCash is bool isCash && isCash != account.IsCash)
            {
                // Checked here so the owner gets a sentence; the unique index underneath would
                // only have given them a 500.
                if (isCash && account.Provider != ProviderNames.Manual)
                    return Results.BadRequest(new { error = "Only a manual account can be a cash wallet — a synced one reports a bank's balance." });
                if (isCash && await WalletExistsAsync(db, account.Currency, except: account.Id))
                    return Results.BadRequest(new { error = DuplicateWallet(account.Currency) });
                account.IsCash = isCash;
            }
            if (req.Name is not null) account.Name = req.Name;
            if (req.Color is not null) account.Color = req.Color;
            if (req.IsArchived is bool archived) account.IsArchived = archived;
            if (req.IsExcluded is bool excluded) account.IsExcluded = excluded;
            var chatId = string.IsNullOrWhiteSpace(req.LowBalanceChatId) ? null : req.LowBalanceChatId.Trim();
            var alertChanged = req.LowBalanceSet &&
                (account.LowBalanceThreshold != req.LowBalanceThreshold || account.LowBalanceChatId != chatId);
            if (alertChanged)
            {
                account.LowBalanceThreshold = req.LowBalanceThreshold;
                account.LowBalanceChatId = chatId;
                // A changed limit is judged fresh — and if the balance already sits below it,
                // the alert goes out right away rather than at the next sync round.
                account.LowBalanceNotifiedAt = null;
            }
            await db.SaveChangesAsync();
            if (alertChanged) _ = Task.Run(() => alerter.CheckAsync(CancellationToken.None));
            return Results.Ok(account.ToDto());
        });

        group.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db) =>
        {
            var account = await db.Accounts.FindAsync(id);
            if (account is null) return Results.NotFound();
            // Sync rediscovers every account the bank reports, so deleting a synced one is not
            // enough on its own — the next round would create it again, transactions and all.
            // Remembering the provider-side id on the connection is what makes a delete stick.
            if (account.ConnectionId is { } connectionId && account.ExternalId is { } externalId)
                (await db.Connections.FindAsync(connectionId))?.Ignore(externalId);
            await ReleaseWithdrawalsIntoAsync(db, account.Id);
            db.Accounts.Remove(account);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });
    }

    private static Task<bool> WalletExistsAsync(SkarbDbContext db, string currency, Guid? except) =>
        db.Accounts.AnyAsync(a => a.IsCash && a.Currency == currency && a.Id != except);

    private static string DuplicateWallet(string currency) =>
        $"You already have a {currency} cash wallet — there is one per currency, so withdrawals always know where to go.";

    /// <summary>
    /// A deleted wallet takes the wallet side of every withdrawal with it, which would leave the
    /// bank side marked as a transfer to nowhere. Those rows go back to being spending, stamped as
    /// the user's decision: otherwise the next sync would open a fresh wallet just to move the
    /// recent ones into it again, and the delete would not have stuck.
    /// </summary>
    private static async Task ReleaseWithdrawalsIntoAsync(SkarbDbContext db, Guid walletId)
    {
        var groups = await db.Transactions
            .Where(t => t.AccountId == walletId && t.Source == TransactionSources.Cash && t.TransferGroupId != null)
            .Select(t => t.TransferGroupId!.Value)
            .ToListAsync();
        if (groups.Count == 0) return;

        var withdrawals = await db.Transactions
            .Where(t => t.AccountId != walletId && t.TransferGroupId != null && groups.Contains(t.TransferGroupId.Value))
            .ToListAsync();
        foreach (var tx in withdrawals)
        {
            tx.IsInternal = false;
            tx.InternalSource = InternalSources.Manual;
            tx.TransferGroupId = null;
            tx.CashAmount = null;
            tx.CashCurrency = null;
        }
    }
}
