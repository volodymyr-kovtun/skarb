using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Common.Services;

public class TransactionIngestor(SkarbDbContext db, ICategorizer categorizer, IOptions<SyncOptions> options)
    : ITransactionIngestor
{
    public async Task<int> IngestAsync(Account account, IReadOnlyCollection<IncomingTransaction> items, CancellationToken ct)
    {
        // The ledger's start date is enforced here rather than in each provider: banks answer
        // with whole statement pages, so however narrow the request window was, this is the
        // gate that actually keeps pre-start history out — of every source, sync included.
        if (options.Value.StartUtc is { } start)
            items = items.Where(i => i.OccurredAtUtc >= start).ToList();
        if (items.Count == 0) return 0;

        var ids = items.Select(i => i.ExternalId).ToList();
        var existing = await db.Transactions
            .Where(t => t.AccountId == account.Id && t.ExternalId != null && ids.Contains(t.ExternalId))
            .ToDictionaryAsync(t => t.ExternalId!, ct);

        var created = 0;
        foreach (var item in items)
        {
            if (existing.TryGetValue(item.ExternalId, out var known))
            {
                // Bank holds can change amount/description/time when they settle.
                known.Amount = item.Amount;
                known.Description = item.Description;
                known.OccurredAt = item.OccurredAtUtc;
                known.TypeCode ??= item.TypeCode;
                known.CounterIban ??= item.CounterIban;
                continue;
            }

            var tx = new Transaction
            {
                AccountId = account.Id,
                ExternalId = item.ExternalId,
                Amount = item.Amount,
                Currency = item.Currency,
                Description = item.Description,
                CounterParty = item.CounterParty,
                CounterIban = item.CounterIban,
                Mcc = item.Mcc,
                TypeCode = item.TypeCode,
                OccurredAt = item.OccurredAtUtc,
                Source = item.Source,
                Note = item.Note,
            };
            // Recording which signal filed it is what later lets a bulk re-file tell a guess
            // apart from a decision the user made.
            if (await categorizer.ResolveAsync(item, ct) is { } verdict)
                (tx.CategoryId, tx.CategorySource) = (verdict.CategoryId, verdict.Source);
            db.Transactions.Add(tx);
            existing[item.ExternalId] = tx; // in-batch duplicates hit the update path above
            created++;
        }

        await db.SaveChangesAsync(ct);
        return created;
    }
}
