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

    /// <summary>
    /// The same, for an edit that reached several accounts at once — a bulk change, or a
    /// withdrawal whose wallet side moved from one wallet to another. Synced accounts among the
    /// ids are skipped like above: their balance is the bank's to report.
    /// </summary>
    public static async Task RecomputeAsync(SkarbDbContext db, IReadOnlyCollection<Guid> accountIds, CancellationToken ct = default)
    {
        if (accountIds.Count == 0) return;
        var accounts = await db.Accounts
            .Where(a => accountIds.Contains(a.Id) && a.Provider == ProviderNames.Manual)
            .ToListAsync(ct);
        foreach (var account in accounts) await RecomputeAsync(db, account, ct);
    }
}
