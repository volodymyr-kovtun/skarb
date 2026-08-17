using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Common.Services;

/// <summary>
/// Manual accounts derive their balance from their transactions (the opening
/// balance is itself a transaction). This is the only place that invariant lives.
/// </summary>
public static class ManualAccountBalance
{
    public static async Task RecomputeAsync(SkarbDbContext db, Account account, CancellationToken ct = default)
    {
        if (account.Provider != ProviderNames.Manual) return;
        account.Balance = await db.Transactions
            .Where(t => t.AccountId == account.Id)
            .SumAsync(t => t.Amount, ct);
        await db.SaveChangesAsync(ct);
    }
}
