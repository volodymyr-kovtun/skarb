using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Common.Services;

/// <summary>What the mirror should do about one bank-side transaction.</summary>
public enum CashMove
{
    /// <summary>Not a withdrawal, or somebody else's decision — nothing to do.</summary>
    Leave,
    /// <summary>A withdrawal: it should be internal, with a wallet side that matches it.</summary>
    Mirror,
    /// <summary>Was mirrored, and is no longer a withdrawal: the wallet side goes, the mark with it.</summary>
    Release,
}

/// <summary>
/// The decisions behind <see cref="CashWithdrawalMirror"/>, kept free of the database so they can
/// be tested as plain functions.
/// </summary>
public static class CashWithdrawal
{
    /// <summary>
    /// SystemKey of the seeded Cash category. The category *is* the signal: rules, the MCC map
    /// and the user all already speak it, so a missed ATM is fixed by filing it under Cash and a
    /// false alarm by filing it anywhere else — no second switch to learn.
    /// </summary>
    public const string CategoryKey = "cash";

    /// <param name="categoryKey">SystemKey of the row's category, if it has one.</param>
    /// <param name="onWallet">Whether the row sits on a cash wallet — spending cash is not withdrawing it.</param>
    public static CashMove Decide(Transaction tx, string? categoryKey, bool onWallet)
    {
        // The wallet side itself. It follows its withdrawal; it is never one.
        if (tx.Source == TransactionSources.Cash) return CashMove.Leave;

        var isWithdrawal = tx.Amount < 0 && categoryKey == CategoryKey && !onWallet;

        // Ours already: keep the wallet in step with it, or let it go once whatever made it a
        // withdrawal is gone — re-filed under another category, say. Exclusion is deliberately
        // not part of that test: excluding a row that is already internal changes no figure, and
        // taking cash back out of the wallet over it would be a side effect nobody asked for.
        if (tx.InternalSource == InternalSources.Cash)
            return isWithdrawal ? CashMove.Mirror : CashMove.Release;

        // Decided by someone else — the user, by hand and in either direction, or a signal that
        // found a real second leg (a wallet top-up typed in before this existed pairs the normal
        // way). Internal with no source recorded is a mark from before provenance: also not ours.
        if (tx.InternalSource is not null || tx.IsInternal) return CashMove.Leave;

        // Excluding a withdrawal by hand was the way to keep it out of spending before wallets
        // existed. Those rows are a decision too; including them again is how they opt in.
        if (tx.IsExcluded) return CashMove.Leave;

        return isWithdrawal ? CashMove.Mirror : CashMove.Leave;
    }

    /// <summary>
    /// What reached the wallet: the user's correction when there is one, otherwise exactly what
    /// left the account.
    /// </summary>
    public static (string Currency, decimal Amount) Received(Transaction withdrawal) => (
        (withdrawal.CashCurrency ?? withdrawal.Currency).ToUpperInvariant(),
        withdrawal.CashAmount ?? -withdrawal.Amount);

    /// <summary>
    /// ExternalId of a withdrawal's wallet side. It is what makes writing that side idempotent:
    /// a sync round and a webhook can both get here for the same withdrawal, and the unique
    /// (AccountId, ExternalId) index turns the second write into an error instead of cash that
    /// exists twice.
    /// </summary>
    public static string LegKey(Transaction withdrawal) => StableId.From("cash", withdrawal.Id.ToString("N"));
}

/// <summary>The wallets <see cref="CashWithdrawalMirror"/> pays into, and how a new one looks.</summary>
public static class CashWallet
{
    /// <summary>The institution wallets are grouped under on the Accounts page and the overview.</summary>
    public const string Bank = "Cash";
    private const string Color = "#426F50";

    /// <summary>Named after its currency — inside a group called Cash that is all there is left to say.</summary>
    public static Account New(string currency) => new()
    {
        Name = currency,
        Bank = Bank,
        Provider = ProviderNames.Manual,
        Currency = currency,
        Color = Color,
        IsCash = true,
    };
}

/// <summary>
/// Moves cash withdrawals to the wallet for their currency by writing the leg the bank never
/// reports. The pair is marked the way detected transfers are — both rows internal, one
/// TransferGroupId, <see cref="InternalSources.Cash"/> as the signal — so everything that already
/// understands transfers (the counting filters, un-marking a pair by hand) understands these.
/// </summary>
/// <remarks>
/// The wallet side is added here directly rather than through <see cref="ITransactionIngestor"/>.
/// The ingestor is the door for transactions that come from somewhere — it dedupes against a
/// provider id and categorizes what is new. This row comes from nowhere but its withdrawal: it
/// must never be categorized (a small one would be filed as cashback), and it has to be found
/// again after moving between wallets, which the ingestor's per-account lookup cannot do.
/// </remarks>
public class CashWithdrawalMirror(SkarbDbContext db, IOptions<SyncOptions> options, ILogger<CashWithdrawalMirror> logger)
    : ICashWithdrawalMirror
{
    public async Task<int> MirrorRecentAsync(CancellationToken ct)
    {
        // The same window transfer detection looks over. OccurredAt is the steady state;
        // CreatedAt catches history a first sync or an import just brought in, so a newly
        // connected bank is read the same way from its first row. What this leaves alone is
        // history that was already in the ledger when wallets arrived: those withdrawals were
        // counted as spending in months the owner has already read, and move only when edited.
        var cutoff = DateTime.UtcNow.AddDays(-options.Value.TransferLookbackDays);
        var rows = await db.Transactions
            .Include(t => t.Account).Include(t => t.Category)
            .Where(t => t.Source != TransactionSources.Cash && (t.OccurredAt >= cutoff || t.CreatedAt >= cutoff))
            .Where(t => t.InternalSource == InternalSources.Cash ||
                        (t.Amount < 0 && t.Category != null && t.Category.SystemKey == CashWithdrawal.CategoryKey))
            .ToListAsync(ct);

        var mirrored = await ReconcileCoreAsync(rows, ct);
        if (mirrored > 0)
            logger.LogInformation("Moved {Count} cash withdrawal(s) to their wallets", mirrored);
        return mirrored;
    }

    public async Task ReconcileAsync(IReadOnlyCollection<Guid> transactionIds, CancellationToken ct)
    {
        if (transactionIds.Count == 0) return;
        var rows = await db.Transactions
            .Include(t => t.Account).Include(t => t.Category)
            .Where(t => transactionIds.Contains(t.Id))
            .ToListAsync(ct);
        await ReconcileCoreAsync(rows, ct);
    }

    private async Task<int> ReconcileCoreAsync(List<Transaction> rows, CancellationToken ct)
    {
        var decisions = rows
            .Select(tx => (Tx: tx, Move: CashWithdrawal.Decide(tx, tx.Category?.SystemKey, tx.Account?.IsCash ?? false)))
            .Where(x => x.Move != CashMove.Leave)
            .ToList();
        if (decisions.Count == 0) return 0;

        var keys = decisions.Select(x => CashWithdrawal.LegKey(x.Tx)).ToList();
        var legs = await db.Transactions
            .Where(t => t.Source == TransactionSources.Cash && t.ExternalId != null && keys.Contains(t.ExternalId))
            .ToDictionaryAsync(t => t.ExternalId!, ct);
        var wallets = await db.Accounts.Where(a => a.IsCash).ToDictionaryAsync(a => a.Currency, ct);

        var touchedWallets = new HashSet<Guid>();
        var mirrored = 0;
        foreach (var (tx, move) in decisions)
        {
            var key = CashWithdrawal.LegKey(tx);
            legs.TryGetValue(key, out var leg);

            if (move == CashMove.Release)
            {
                if (leg is not null)
                {
                    touchedWallets.Add(leg.AccountId);
                    db.Transactions.Remove(leg);
                }
                // Back to an ordinary transaction with nothing decided, which is what it was
                // before the mirror found it. The correction described a wallet side that is gone.
                tx.IsInternal = false;
                tx.InternalSource = null;
                tx.TransferGroupId = null;
                tx.CashAmount = null;
                tx.CashCurrency = null;
                continue;
            }

            var (currency, amount) = CashWithdrawal.Received(tx);
            if (!wallets.TryGetValue(currency, out var wallet))
            {
                // Wallets open themselves: the first withdrawal in a currency is the moment one
                // is needed, and asking for it to be set up first would mean the feature silently
                // does nothing until someone reads the manual.
                wallet = CashWallet.New(currency);
                db.Accounts.Add(wallet);
                wallets[currency] = wallet;
            }
            // Archiving a wallet opts its currency out. Nothing new is moved there, and what is
            // already there stays as it was — a closed account should not keep changing.
            if (wallet.IsArchived) continue;

            if (leg is null)
            {
                leg = new Transaction
                {
                    ExternalId = key,
                    Description = tx.Description,
                    Source = TransactionSources.Cash,
                    IsInternal = true,
                    InternalSource = InternalSources.Cash,
                };
                db.Transactions.Add(leg);
                mirrored++;
            }
            else if (leg.AccountId != wallet.Id)
            {
                touchedWallets.Add(leg.AccountId);
            }

            // Everything about the wallet side that follows from the withdrawal is restated on
            // every pass, so a hold that settles at a different amount, or a correction that
            // moves the cash to another currency, lands here without a special case for either.
            leg.AccountId = wallet.Id;
            leg.Amount = amount;
            leg.Currency = currency;
            leg.OccurredAt = tx.OccurredAt;
            leg.TransferGroupId = tx.TransferGroupId ??= Guid.NewGuid();
            tx.IsInternal = true;
            tx.InternalSource = InternalSources.Cash;
            touchedWallets.Add(wallet.Id);
        }

        if (!db.ChangeTracker.HasChanges()) return 0;
        await db.SaveChangesAsync(ct);
        await ManualAccountBalance.RecomputeAsync(db, touchedWallets, ct);
        return mirrored;
    }
}
