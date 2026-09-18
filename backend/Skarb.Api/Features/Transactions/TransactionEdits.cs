using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Transactions;

/// <summary>
/// The edits that carry provenance, written once so that changing one row and changing three
/// hundred cannot drift apart: both stamp the user's decision the same way, which is what keeps
/// automated passes from overruling either.
/// </summary>
internal static class TransactionEdits
{
    /// <summary>
    /// Choosing a category by hand is a decision, so it is recorded as one: a later bulk re-file
    /// steps around it. Clearing it back to uncategorized decides nothing.
    /// </summary>
    public static void SetCategory(Transaction tx, Guid? categoryId)
    {
        tx.CategoryId = categoryId;
        tx.CategorySource = categoryId is null ? null : CategorySources.Manual;
    }

    /// <summary>
    /// Marks or un-marks rows as internal by hand. Rows already in the requested state are left
    /// alone, provenance included — re-saving a detected transfer does not make it a manual one.
    /// </summary>
    /// <returns>
    /// Accounts that lost a row to this, whose balance the caller recomputes once it has saved.
    /// </returns>
    public static async Task<HashSet<Guid>> SetInternalAsync(
        SkarbDbContext db, IReadOnlyCollection<Transaction> rows, bool isInternal, CancellationToken ct)
    {
        var lostRows = new HashSet<Guid>();
        var changing = rows.Where(t => t.IsInternal != isInternal).ToList();

        if (isInternal)
        {
            foreach (var tx in changing)
            {
                tx.IsInternal = true;
                tx.InternalSource = InternalSources.Manual;
            }
            return lostRows;
        }

        // Un-marking one leg of a transfer releases all of it. Every leg is stamped manual:
        // without that they look untouched to detection, which pairs them straight back up on
        // the next sync.
        var groupIds = changing.Where(t => t.TransferGroupId is not null)
            .Select(t => t.TransferGroupId!.Value).Distinct().ToList();
        var partners = groupIds.Count == 0 ? [] : await db.Transactions
            .Where(t => t.TransferGroupId != null && groupIds.Contains(t.TransferGroupId.Value))
            .ToListAsync(ct);

        foreach (var leg in changing.Concat(partners).Distinct())
        {
            // The wallet side of a cash withdrawal is a row Skarb wrote, and only because the
            // pair was a transfer. Left behind it would be money from nowhere in the wallet, so
            // it is removed rather than released.
            if (leg.Source == TransactionSources.Cash)
            {
                lostRows.Add(leg.AccountId);
                db.Transactions.Remove(leg);
                continue;
            }
            leg.IsInternal = false;
            leg.TransferGroupId = null;
            leg.InternalSource = InternalSources.Manual;
            leg.CashAmount = null;
            leg.CashCurrency = null;
        }
        return lostRows;
    }
}
