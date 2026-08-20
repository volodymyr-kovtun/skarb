using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Accounts;

public record CreateAccountRequest(string Name, string Bank, string Currency, decimal Balance, string? Color);
/// <param name="LowBalanceSet">Distinguishes "leave the alert alone" from "turn it off" (null threshold), like CategorySet on transactions.</param>
public record UpdateAccountRequest(
    string? Name, string? Color, bool? IsArchived, bool? IsExcluded,
    bool LowBalanceSet = false, decimal? LowBalanceThreshold = null, string? LowBalanceChatId = null);

public class AccountEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/accounts");

        group.MapPost("/", async (CreateAccountRequest req, SkarbDbContext db) =>
        {
            var account = new Account
            {
                Name = req.Name,
                Bank = string.IsNullOrWhiteSpace(req.Bank) ? "Manual" : req.Bank,
                Provider = ProviderNames.Manual,
                Currency = req.Currency.ToUpperInvariant(),
                Balance = req.Balance,
            };
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
            db.Accounts.Remove(account);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });
    }
}
