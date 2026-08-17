using Microsoft.EntityFrameworkCore;

namespace Skarb.Api.Common.Persistence;

public static class TransactionQueries
{
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
