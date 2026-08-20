using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Persistence;

public static class TransactionQueries
{
    /// <summary>
    /// Narrows to transactions on accounts that are part of the owner's picture. An excluded
    /// account is live but deliberately not counted; an archived one is closed. Either way the
    /// overview and the transaction list should behave as though its money isn't there — the
    /// accounts page is the one place both still report a balance.
    /// </summary>
    public static IQueryable<Transaction> OnCountedAccounts(this IQueryable<Transaction> q) =>
        q.Where(t => t.Account != null && !t.Account.IsExcluded && !t.Account.IsArchived);

    /// <summary>
    /// Incremental-sync watermark: the newest synced transaction per account,
    /// fetched in one grouped query. Accounts with no synced history are absent.
    /// </summary>
    public static async Task<Dictionary<Guid, DateTime>> LastSyncedByAccountAsync(
        this SkarbDbContext db, IReadOnlyCollection<Guid> accountIds, CancellationToken ct)
    {
        var rows = await db.Transactions
            .Where(t => accountIds.Contains(t.AccountId) && t.ExternalId != null)
            .GroupBy(t => t.AccountId)
            .Select(g => new { g.Key, Max = g.Max(t => t.OccurredAt) })
            .ToListAsync(ct);
        return rows.ToDictionary(x => x.Key, x => x.Max);
    }
}
