using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Common.Services;

/// <summary>
/// Marks transfers between the user's own accounts as internal using two signals:
/// 1. the counterparty IBAN belongs to one of the user's accounts;
/// 2. an opposite-amount pair in the same currency lands on two different accounts
///    within 72 hours (classic A→B transfer where both banks are synced).
/// Both legs get a shared TransferGroupId so they can be un-marked together.
/// </summary>
public partial class TransferDetector(SkarbDbContext db, IOptions<SyncOptions> options, ILogger<TransferDetector> logger) : ITransferDetector
{
    public async Task<int> DetectAsync(CancellationToken ct)
    {
        var pairWindow = TimeSpan.FromHours(options.Value.TransferPairWindowHours);
        var cutoff = DateTime.UtcNow.AddDays(-options.Value.TransferLookbackDays);
        var marked = 0;

        var ownIbans = await db.Accounts
            .Where(a => a.Iban != null && a.Iban != "")
            .Select(a => new { a.Id, a.Iban })
            .ToListAsync(ct);
        var ibanToAccount = ownIbans.ToDictionary(x => Normalize(x.Iban!), x => x.Id);

        // CreatedAt catches historical rows that a first sync/import just brought in;
        // OccurredAt catches the steady-state window.
        var recent = await db.Transactions
            .Where(t => !t.IsExcluded && (t.OccurredAt >= cutoff || t.CreatedAt >= cutoff))
            .OrderBy(t => t.OccurredAt)
            .ToListAsync(ct);

        // Signal 1: counter-IBAN is one of our own accounts (works even if the other bank isn't synced yet).
        foreach (var tx in recent.Where(t => !t.IsInternal && t.CounterIban != null))
        {
            if (ibanToAccount.TryGetValue(Normalize(tx.CounterIban!), out var otherAccountId) &&
                otherAccountId != tx.AccountId)
            {
                tx.IsInternal = true;
                marked++;
            }
        }

        // Signal 2: bank-issued shared reference on both legs (e.g. PKO currency exchange
        // "FX18628069 EUR/PLN 4,26 DEBIT" + "... CREDIT") — catches cross-currency moves the
        // amount-based pairing below can't.
        var byRef = recent
            .Where(t => t.TransferGroupId == null)
            .Select(t => (Tx: t, Ref: SharedReference(t)))
            .Where(x => x.Ref is not null)
            .GroupBy(x => x.Ref!)
            .Where(g => g.Select(x => x.Tx.AccountId).Distinct().Count() >= 2 &&
                        g.Any(x => x.Tx.Amount < 0) && g.Any(x => x.Tx.Amount > 0));
        foreach (var g in byRef)
        {
            var group = Guid.NewGuid();
            foreach (var (tx, _) in g)
            {
                if (!tx.IsInternal) marked++;
                tx.IsInternal = true;
                tx.TransferGroupId = group;
            }
        }

        // Signal 3: opposite legs on two different accounts, same currency, close in time.
        var unpaired = recent.Where(t => t.TransferGroupId == null).ToList();
        var candidates = unpaired.Where(t => t.Amount > 0).ToList();

        foreach (var outgoing in unpaired.Where(t => t.Amount < 0))
        {
            var match = candidates
                .Where(c => c.TransferGroupId == null &&
                            c.AccountId != outgoing.AccountId &&
                            c.Currency == outgoing.Currency &&
                            c.Amount == -outgoing.Amount &&
                            (c.OccurredAt - outgoing.OccurredAt).Duration() <= pairWindow)
                .OrderBy(c => (c.OccurredAt - outgoing.OccurredAt).Duration())
                .FirstOrDefault();
            if (match is null) continue;

            var group = Guid.NewGuid();
            foreach (var leg in new[] { outgoing, match })
            {
                if (!leg.IsInternal) marked++;
                leg.IsInternal = true;
                leg.TransferGroupId = group;
            }
        }

        if (marked > 0)
        {
            await db.SaveChangesAsync(ct);
            logger.LogInformation("Transfer detection marked {Count} transaction(s) as internal", marked);
        }
        return marked;
    }

    private static string Normalize(string iban) => iban.Replace(" ", "").ToUpperInvariant();

    /// <summary>
    /// A bank-issued token that appears on both legs of one operation: currently PKO's
    /// "FX&lt;digits&gt;" exchange reference. Extend here as other banks reveal theirs.
    /// </summary>
    private static string? SharedReference(Domain.Transaction t)
    {
        foreach (var text in new[] { t.Description, t.Note })
        {
            if (string.IsNullOrEmpty(text)) continue;
            var m = FxRef().Match(text);
            if (m.Success) return m.Value.ToUpperInvariant();
        }
        return null;
    }

    [System.Text.RegularExpressions.GeneratedRegex(@"\bFX\d{6,}\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase)]
    private static partial System.Text.RegularExpressions.Regex FxRef();
}
