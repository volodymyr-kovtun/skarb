using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Accounts;

public record CreateAccountRequest(string Name, string Bank, string Currency, decimal Balance, string? Color);
public record UpdateAccountRequest(string? Name, string? Color, bool? IsArchived);

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

        group.MapPatch("/{id:guid}", async (Guid id, UpdateAccountRequest req, SkarbDbContext db) =>
        {
            var account = await db.Accounts.FindAsync(id);
            if (account is null) return Results.NotFound();
            if (req.Name is not null) account.Name = req.Name;
            if (req.Color is not null) account.Color = req.Color;
            if (req.IsArchived is bool archived) account.IsArchived = archived;
            await db.SaveChangesAsync();
            return Results.Ok(account.ToDto());
        });

        group.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db) =>
        {
            var account = await db.Accounts.FindAsync(id);
            if (account is null) return Results.NotFound();
            db.Accounts.Remove(account);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });
    }
}
