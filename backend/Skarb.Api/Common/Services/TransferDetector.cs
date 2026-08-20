using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Common.Services;

/// <summary>
/// Marks transfers between the user's own accounts as internal using three signals:
/// 1. the counterparty IBAN belongs to one of the user's accounts;
/// 2. a bank-issued reference shared by both legs of one operation;
/// 3. an opposite-amount pair in the same currency lands on two different accounts
///    within the pair window (classic A→B transfer where both banks are synced).
/// Both legs get a shared TransferGroupId so they can be un-marked together, and every
/// decision records the signal behind it in InternalSource — the user's own calls are
/// tagged too, which is what keeps detection from overruling them on the next sync.
/// </summary>
public partial class TransferDetector(SkarbDbContext db, IOptions<SyncOptions> options, ILogger<TransferDetector> logger) : ITransferDetector
{
    public async Task<int> DetectAsync(CancellationToken ct)
    {
        var pairWindow = TimeSpan.FromHours(options.Value.TransferPairWindowHours);
        var cutoff = DateTime.UtcNow.AddDays(-options.Value.TransferLookbackDays);
        var marked = 0;
        var released = 0;

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

        // Whatever the user decided by hand outranks every signal below, in both directions:
        // a row they un-marked stays un-marked instead of coming back on the next sync.
        var detectorOwned = recent.Where(t => t.InternalSource != InternalSources.Manual).ToList();

        // Signal 1: counter-IBAN is one of our own accounts (works even if the other bank isn't synced yet).
        foreach (var tx in detectorOwned.Where(t => !t.IsInternal && t.CounterIban != null))
        {
            if (ibanToAccount.TryGetValue(Normalize(tx.CounterIban!), out var otherAccountId) &&
                otherAccountId != tx.AccountId)
            {
                tx.IsInternal = true;
                tx.InternalSource = InternalSources.Iban;
                marked++;
            }
        }

        // Signal 2: bank-issued shared reference on both legs (e.g. PKO currency exchange
        // "FX18628069 EUR/PLN 4,26 DEBIT" + "... CREDIT") — catches cross-currency moves the
        // amount-based pairing below can't.
        var byRef = detectorOwned
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
                tx.InternalSource = InternalSources.Reference;
                tx.TransferGroupId = group;
            }
        }

        // Signal 3: opposite legs on two different accounts, same currency, close in time.
        // This pass re-examines every row it owns, so a pairing made before the other bank was
        // connected can still be corrected once the missing leg turns up. Signal 1's rows join in
        // (only one side of a PKO→Monobank move carries an IBAN, and pairing is what marks the
        // other), but they keep their own source: the IBAN stands on its own as evidence.
        var pairable = detectorOwned
            .Where(t => t.InternalSource is null or InternalSources.Pair or InternalSources.Iban)
            .ToList();
        var groupBefore = pairable.ToDictionary(t => t.Id, t => t.TransferGroupId);
        var pairs = PairLegs(pairable, pairWindow);
        var paired = pairs.SelectMany(p => new[] { p.Debit.Id, p.Credit.Id }).ToHashSet();

        foreach (var (debit, credit) in pairs)
        {
            // An unchanged pairing keeps its group id, so a re-run writes nothing.
            if (debit.TransferGroupId is Guid kept && credit.TransferGroupId == kept) continue;

            var group = Guid.NewGuid();
            foreach (var leg in new[] { debit, credit })
            {
                if (!leg.IsInternal) marked++;
                leg.IsInternal = true;
                if (leg.InternalSource != InternalSources.Iban) leg.InternalSource = InternalSources.Pair;
                leg.TransferGroupId = group;
            }
        }

        // Releasing only ever follows a re-pairing: a leg whose partner was won by a closer match
        // goes back to being an ordinary transaction. A leg that merely has no partner this run —
        // because the other side aged out of the window, say — is left exactly as it was.
        foreach (var leg in pairable)
        {
            if (paired.Contains(leg.Id)) continue;
            if (groupBefore[leg.Id] is not Guid group) continue;
            if (!pairable.Any(other => other.Id != leg.Id && groupBefore[other.Id] == group && paired.Contains(other.Id)))
                continue;

            // Its own IBAN still says this is a transfer, so losing the partner costs it the
            // group, not the mark.
            leg.TransferGroupId = null;
            if (leg.InternalSource == InternalSources.Iban) continue;

            leg.IsInternal = false;
            leg.InternalSource = null;
            released++;
        }

        // Gating on the counters alone would drop a run that only re-pointed a group between two
        // rows that were internal already — a change worth saving that marks and releases nothing.
        if (db.ChangeTracker.HasChanges())
        {
            await db.SaveChangesAsync(ct);
            logger.LogInformation(
                "Transfer detection marked {Marked} transaction(s) as internal, released {Released} whose partner found a closer match",
                marked, released);
        }
        return marked;
    }

    /// <summary>
    /// Pairs debits with credits closest in time first. Going in time order instead would let an
    /// early leg claim a credit that a later one matches to the second — which is how a transfer
    /// ends up with only one of its two legs marked. Ties break on Id so runs stay reproducible.
    /// </summary>
    internal static List<(Transaction Debit, Transaction Credit)> PairLegs(
        IReadOnlyList<Transaction> legs, TimeSpan window)
    {
        var credits = legs.Where(t => t.Amount > 0).ToList();
        var candidates =
            from debit in legs.Where(t => t.Amount < 0)
            from credit in credits
            where credit.AccountId != debit.AccountId &&
                  credit.Currency == debit.Currency &&
                  credit.Amount == -debit.Amount
            let delta = (credit.OccurredAt - debit.OccurredAt).Duration()
            where delta <= window
            orderby delta, debit.Id, credit.Id
            select (Debit: debit, Credit: credit);

        var taken = new HashSet<Guid>();
        var pairs = new List<(Transaction, Transaction)>();
        foreach (var (debit, credit) in candidates)
        {
            if (taken.Contains(debit.Id) || taken.Contains(credit.Id)) continue;
            taken.Add(debit.Id);
            taken.Add(credit.Id);
            pairs.Add((debit, credit));
        }
        return pairs;
    }

    private static string Normalize(string iban) => iban.Replace(" ", "").ToUpperInvariant();

    /// <summary>
    /// A bank-issued token that appears on both legs of one operation: currently PKO's
    /// "FX&lt;digits&gt;" exchange reference. Extend here as other banks reveal theirs.
    /// </summary>
    private static string? SharedReference(Transaction t)
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
