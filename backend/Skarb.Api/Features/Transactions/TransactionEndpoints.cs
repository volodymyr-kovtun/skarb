using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Features.Transactions;

public record CreateTransactionRequest(
    Guid AccountId, decimal Amount, string? Currency, string Description,
    Guid? CategoryId, List<Guid>? TagIds, DateTime OccurredAt, string? Note);

/// <summary>What a manual category change could be turned into: a keyword rule, and what it covers.</summary>
public record RuleSuggestionResponse(
    string? Pattern, List<string> Alternatives, ExistingRuleDto? ExistingRule,
    RuleMatchCounts Matches, List<TransactionDto> Sample);

public record ExistingRuleDto(Guid Id, string Pattern, CategoryDto Category);
/// <param name="Untouched">Matches filed by hand, or before provenance was recorded. Left alone by default.</param>
public record RuleMatchCounts(int Uncategorized, int Automatic, int Untouched);

/// <param name="CashSet">
/// Distinguishes "leave the wallet side alone" from "it received exactly what left the account"
/// (null amount, same currency), like CategorySet does for categories.
/// </param>
/// <param name="CashAmount">Null with another currency means "convert it for me, at today's rate".</param>
public record UpdateTransactionRequest(
    string? Description, decimal? Amount, DateTime? OccurredAt, string? Note,
    bool? IsExcluded, bool? IsInternal, bool CategorySet, Guid? CategoryId, List<Guid>? TagIds,
    bool CashSet = false, string? CashCurrency = null, decimal? CashAmount = null);

/// <summary>
/// One edit applied to many rows. Every field is optional and the ones left out are left alone,
/// so the same call serves "tag these", "file these" and "these are transfers".
/// </summary>
/// <param name="CategorySet">Distinguishes "leave categories alone" from "clear them".</param>
public record BulkUpdateRequest(
    List<Guid> Ids, bool CategorySet = false, Guid? CategoryId = null,
    List<Guid>? AddTagIds = null, List<Guid>? RemoveTagIds = null,
    bool? IsInternal = null, bool? IsExcluded = null);

/// <summary>
/// The transaction list's filters, bound from the query string. Shared by the page of rows and by
/// "select everything that matches", so the two can never disagree about what a filter means.
/// </summary>
public record TransactionFilter(
    Guid? AccountId, Guid? CategoryId, Guid[]? TagIds, string? Search,
    DateTime? From, DateTime? To, bool? Uncategorized, bool? InternalOnly, bool? InvestmentsOnly,
    bool? HideInternal)
{
    public IQueryable<Transaction> Apply(IQueryable<Transaction> q)
    {
        // Excluded and archived accounts are out of the picture, so their transactions stay out
        // of the list too. Naming one in the account filter is the deliberate way back in.
        if (AccountId is Guid a) q = q.Where(t => t.AccountId == a);
        else q = q.OnCountedAccounts();
        if (CategoryId is Guid c) q = q.Where(t => t.CategoryId == c);
        // Several tags read as "any of these" — narrowing to transactions carrying all of
        // them would return almost nothing, since a transaction rarely wears two labels.
        if (TagIds is { Length: > 0 } tagIds) q = q.Where(t => t.Tags.Any(x => tagIds.Contains(x.Id)));
        if (Uncategorized == true) q = q.Where(t => t.CategoryId == null && !t.IsInternal);
        if (InternalOnly == true) q = q.Where(t => t.IsInternal);
        // Transfers between the owner's own accounts are noise once you're reading the
        // list as a spending log, so they can be dropped without touching any other filter.
        else if (HideInternal == true) q = q.Where(t => !t.IsInternal);
        if (InvestmentsOnly == true) q = q.Where(t => t.Category != null && t.Category.Kind == CategoryKinds.Investment);
        if (From is DateTime f) q = q.Where(t => t.OccurredAt >= DateTime.SpecifyKind(f, DateTimeKind.Utc));
        if (To is DateTime to) q = q.Where(t => t.OccurredAt < DateTime.SpecifyKind(to, DateTimeKind.Utc).AddDays(1));
        if (!string.IsNullOrWhiteSpace(Search))
        {
            var s = $"%{Search}%";
            q = q.Where(t =>
                EF.Functions.ILike(t.Description, s) ||
                (t.CounterParty != null && EF.Functions.ILike(t.CounterParty, s)) ||
                (t.Note != null && EF.Functions.ILike(t.Note, s)));
        }
        return q;
    }
}

public class TransactionEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/transactions");

        group.MapGet("/", async (
            SkarbDbContext db, [AsParameters] TransactionFilter filter, int page = 1, int pageSize = 50) =>
        {
            var q = filter.Apply(db.Transactions
                .Include(t => t.Account).Include(t => t.Category).Include(t => t.Tags));

            var total = await q.CountAsync();
            var items = await q.OrderByDescending(t => t.OccurredAt).ThenByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize).Take(pageSize)
                .ToListAsync();
            return new PagedResult<TransactionDto>(items.Select(t => t.ToDto()).ToList(), total, page, pageSize);
        });

        // "Select all 340 that match" — the list only ever holds a page, and a bulk edit that
        // stops at the fold is how half a cleanup gets done. Newest first like the list, so when
        // the cap bites it is the far end of the history that is left out.
        group.MapGet("/ids", async (SkarbDbContext db, [AsParameters] TransactionFilter filter, CancellationToken ct) =>
        {
            var q = filter.Apply(db.Transactions);
            var total = await q.CountAsync(ct);
            var ids = await q.OrderByDescending(t => t.OccurredAt).ThenByDescending(t => t.CreatedAt)
                .Select(t => t.Id).Take(MaxBulk).ToListAsync(ct);
            return Results.Ok(new { ids, total });
        });

        group.MapPost("/", async (
            CreateTransactionRequest req, SkarbDbContext db, ICategorizer categorizer,
            ICashWithdrawalMirror cashMirror, CancellationToken ct) =>
        {
            var account = await db.Accounts.FindAsync([req.AccountId], ct);
            if (account is null) return Results.BadRequest(new { error = "Account not found" });

            var tx = new Transaction
            {
                AccountId = account.Id,
                Amount = req.Amount,
                Currency = (req.Currency ?? account.Currency).ToUpperInvariant(),
                Description = req.Description,
                CategoryId = req.CategoryId,
                CategorySource = req.CategoryId is null ? null : CategorySources.Manual,
                OccurredAt = DateTime.SpecifyKind(req.OccurredAt, DateTimeKind.Utc),
                Note = req.Note,
                Source = TransactionSources.Manual,
            };
            // A hand-added transaction deserves the same rules a synced one gets — without this
            // the only way to categorize one is to do it yourself, every time.
            if (tx.CategoryId is null)
            {
                var probe = new IncomingTransaction(tx.Id.ToString(), tx.Amount, tx.Currency,
                    tx.Description, tx.OccurredAt, tx.Source) { Note = tx.Note };
                if (await categorizer.ResolveAsync(probe, ct) is { } verdict)
                    (tx.CategoryId, tx.CategorySource) = (verdict.CategoryId, verdict.Source);
            }
            if (req.TagIds is { Count: > 0 })
                tx.Tags = await db.Tags.Where(t => req.TagIds.Contains(t.Id)).ToListAsync();

            db.Transactions.Add(tx);
            await db.SaveChangesAsync();
            // A withdrawal typed in by hand — from a bank that only arrives by CSV, say — moves
            // to the wallet the same way a synced one does.
            await cashMirror.ReconcileAsync([tx.Id], ct);
            await ManualAccountBalance.RecomputeAsync(db, account);

            await db.Entry(tx).Reference(t => t.Account).LoadAsync();
            await db.Entry(tx).Reference(t => t.Category).LoadAsync();
            return Results.Created($"/api/transactions/{tx.Id}", tx.ToDto());
        });

        group.MapPatch("/{id:guid}", async (
            Guid id, UpdateTransactionRequest req, SkarbDbContext db,
            ICashWithdrawalMirror cashMirror, IExchangeRateService fx, CancellationToken ct) =>
        {
            var tx = await db.Transactions
                .Include(t => t.Account).Include(t => t.Category).Include(t => t.Tags)
                .FirstOrDefaultAsync(t => t.Id == id);
            if (tx is null) return Results.NotFound();

            // Worked out before anything is touched, so a correction that cannot be applied
            // rejects the whole edit instead of saving half of it.
            (string? Currency, decimal? Amount)? received = null;
            if (req.CashSet)
            {
                var (resolved, error) = await ResolveReceivedAsync(tx, req, db, fx, ct);
                if (error is not null) return Results.BadRequest(new { error });
                received = resolved;
            }

            if (req.Description is not null) tx.Description = req.Description;
            if (req.Note is not null) tx.Note = req.Note.Length == 0 ? null : req.Note;
            if (req.IsExcluded is bool excl) tx.IsExcluded = excl;
            if (req.OccurredAt is DateTime occ) tx.OccurredAt = DateTime.SpecifyKind(occ, DateTimeKind.Utc);
            if (req.Amount is decimal amount && tx.Source == TransactionSources.Manual)
                tx.Amount = amount;
            if (req.CategorySet) TransactionEdits.SetCategory(tx, req.CategoryId);
            if (req.TagIds is not null)
                tx.Tags = await db.Tags.Where(t => req.TagIds.Contains(t.Id)).ToListAsync();
            if (received is { } cash) (tx.CashCurrency, tx.CashAmount) = (cash.Currency, cash.Amount);

            var touched = new HashSet<Guid> { tx.AccountId };
            if (req.IsInternal is bool isInternal)
                touched.UnionWith(await TransactionEdits.SetInternalAsync(db, [tx], isInternal, ct));

            await db.SaveChangesAsync();
            // After the save, because the mirror reads the row as the edit left it: a category
            // that now says Cash, one that no longer does, or a correction to carry across.
            await cashMirror.ReconcileAsync([tx.Id], ct);
            await ManualAccountBalance.RecomputeAsync(db, touched, ct);

            // Un-marking the wallet side of a withdrawal removes it. The edit still answers with
            // the row as it last stood, since a client that sent a PATCH is waiting for one.
            if (db.Entry(tx).State != EntityState.Detached)
                await db.Entry(tx).Reference(t => t.Category).LoadAsync();
            return Results.Ok(tx.ToDto());
        });

        // One edit over a selection. Provenance is stamped exactly as the single-row edit does
        // it — these are the user's decisions too, just more of them at once.
        group.MapPost("/bulk", async (
            BulkUpdateRequest req, SkarbDbContext db, ICashWithdrawalMirror cashMirror, CancellationToken ct) =>
        {
            var ids = req.Ids?.Distinct().ToList() ?? [];
            if (ids.Count == 0) return Results.BadRequest(new { error = "Select at least one transaction." });
            if (ids.Count > MaxBulk)
                return Results.BadRequest(new { error = $"That is more than {MaxBulk} transactions — narrow the selection." });
            if (req.CategorySet && req.CategoryId is Guid categoryId && !await db.Categories.AnyAsync(c => c.Id == categoryId, ct))
                return Results.BadRequest(new { error = "Category not found." });

            var addTagIds = req.AddTagIds ?? [];
            var removeTagIds = req.RemoveTagIds ?? [];
            var retag = addTagIds.Count > 0 || removeTagIds.Count > 0;

            var query = db.Transactions.Where(t => ids.Contains(t.Id));
            if (retag) query = query.Include(t => t.Tags);
            var rows = await query.ToListAsync(ct);

            var touched = rows.Select(t => t.AccountId).ToHashSet();
            // First, because releasing a withdrawal removes its wallet side — and a row that is
            // on its way out should not be handed a tag or a category on the way.
            if (req.IsInternal is bool isInternal)
            {
                touched.UnionWith(await TransactionEdits.SetInternalAsync(db, rows, isInternal, ct));
                rows = rows.Where(t => db.Entry(t).State != EntityState.Deleted).ToList();
            }

            // What each row was filed as before, handed back so the client can offer an undo
            // through the same revert the rule sheet uses — no history is kept server-side.
            var reverts = new List<RuleApplication.Applied>();
            if (req.CategorySet)
            {
                foreach (var tx in rows.Where(t => t.CategoryId != req.CategoryId))
                {
                    reverts.Add(new RuleApplication.Applied(tx.Id, tx.CategoryId, tx.CategorySource));
                    TransactionEdits.SetCategory(tx, req.CategoryId);
                }
            }

            if (req.IsExcluded is bool excluded)
                foreach (var tx in rows) tx.IsExcluded = excluded;

            if (retag)
            {
                var adding = await db.Tags.Where(t => addTagIds.Contains(t.Id)).ToListAsync(ct);
                foreach (var tx in rows)
                {
                    tx.Tags.RemoveAll(t => removeTagIds.Contains(t.Id));
                    foreach (var tag in adding.Where(tag => tx.Tags.All(t => t.Id != tag.Id)))
                        tx.Tags.Add(tag);
                }
            }

            await db.SaveChangesAsync(ct);
            await cashMirror.ReconcileAsync(rows.Select(t => t.Id).ToList(), ct);
            await ManualAccountBalance.RecomputeAsync(db, touched, ct);
            return Results.Ok(new { updated = rows.Count, reverts });
        });

        // What an ATM abroad most likely paid out: the bank's amount at today's rate. Only ever
        // a starting point for the correction — the rate is today's rather than the day's, and
        // the machine's own fee is in the bank's figure but never reached the wallet.
        group.MapGet("/{id:guid}/cash-estimate", async (
            Guid id, string currency, SkarbDbContext db, IExchangeRateService fx, CancellationToken ct) =>
        {
            var tx = await db.Transactions.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id, ct);
            if (tx is null) return Results.NotFound();
            return Results.Ok(new { amount = await EstimateAsync(fx, tx, currency.Trim().ToUpperInvariant(), ct) });
        });

        // What the manual category change on this transaction could be generalised into. Called
        // when the offer sheet opens, then again — debounced — as the keyword is edited, so the
        // counts under the field are always the real ones.
        group.MapGet("/{id:guid}/rule-suggestion", async (
            Guid id, string? pattern, SkarbDbContext db, CancellationToken ct) =>
        {
            var tx = await db.Transactions.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id, ct);
            if (tx is null) return Results.NotFound();
            // Nothing to generalise from a row with no category, and keyword rules never run on
            // transfers between the owner's own accounts.
            if (tx.CategoryId is not Guid categoryId || tx.IsInternal)
                return Results.Ok(Nothing());

            var typed = !string.IsNullOrWhiteSpace(pattern);
            var suggestion = MerchantKeyword.For(tx.Description, tx.CounterParty, tx.Note, tx.TypeCode);
            var chosen = typed ? pattern!.Trim() : suggestion.Keyword;
            if (string.IsNullOrWhiteSpace(chosen)) return Results.Ok(Nothing());

            // Only an exact keyword collision is offered as a repoint. A rule that merely also
            // fires here ("fee") is someone else's rule and must not be redirected by this row.
            var existing = await db.CategoryRules.Include(r => r.Category)
                .FirstOrDefaultAsync(r => r.Pattern.ToLower() == chosen.ToLower(), ct);
            // A rule that already says what the user just said leaves nothing to offer — but only
            // suppress the unprompted offer. A keyword typed by hand gets its real counts back
            // however redundant it turns out to be, rather than a sheet that goes blank.
            if (!typed && existing is not null && existing.CategoryId == categoryId)
                return Results.Ok(Nothing());

            var matches = await RuleApplication.FindAsync(db, chosen, categoryId, ct);
            var alternatives = new[] { suggestion.Keyword }.Concat(suggestion.Alternatives)
                .Where(a => !string.IsNullOrWhiteSpace(a) && !string.Equals(a, chosen, StringComparison.OrdinalIgnoreCase))
                .Select(a => a!).Distinct().ToList();

            return Results.Ok(new RuleSuggestionResponse(
                chosen,
                alternatives,
                existing is null ? null : new ExistingRuleDto(existing.Id, existing.Pattern, existing.Category!.ToDto()),
                new RuleMatchCounts(matches.Uncategorized.Count, matches.Automatic.Count, matches.Untouched.Count),
                // Newest first across all three buckets — concatenating them would sort by
                // provenance, which is not how anyone reads a list of their own transactions.
                matches.InScope(RuleScopes.All)
                    .OrderByDescending(t => t.OccurredAt).ThenByDescending(t => t.CreatedAt)
                    .Take(SampleSize).Select(t => t.ToDto()).ToList()));
        });

        group.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db, CancellationToken ct) =>
        {
            var tx = await db.Transactions.FirstOrDefaultAsync(t => t.Id == id, ct);
            if (tx is null) return Results.NotFound();

            var touched = new HashSet<Guid> { tx.AccountId };
            // Either half of a cash withdrawal takes the pairing with it. Deleting the wallet side
            // is un-marking the pair by another name: the withdrawal goes back to being spending,
            // stamped as the user's call so the next sync does not quietly move it again. Deleting
            // the withdrawal takes the wallet side along, since nothing is left for it to mirror.
            if (tx.Source == TransactionSources.Cash)
                touched.UnionWith(await TransactionEdits.SetInternalAsync(db, [tx], false, ct));
            else if (tx.InternalSource == InternalSources.Cash)
            {
                var key = CashWithdrawal.LegKey(tx);
                var leg = await db.Transactions
                    .FirstOrDefaultAsync(t => t.Source == TransactionSources.Cash && t.ExternalId == key, ct);
                if (leg is not null)
                {
                    touched.Add(leg.AccountId);
                    db.Transactions.Remove(leg);
                }
            }

            if (db.Entry(tx).State != EntityState.Deleted) db.Transactions.Remove(tx);
            await db.SaveChangesAsync(ct);
            await ManualAccountBalance.RecomputeAsync(db, touched, ct);
            return Results.NoContent();
        });
    }

    /// <summary>How many matching transactions the offer sheet shows as evidence for its count.</summary>
    private const int SampleSize = 3;

    /// <summary>
    /// The most one bulk edit takes, and the most "select all" hands out. Far past anything a
    /// cleanup needs; it is there so a selection cannot grow into a request that times out.
    /// </summary>
    private const int MaxBulk = 5000;

    /// <summary>A null pattern is how the API says "do not offer anything here".</summary>
    private static RuleSuggestionResponse Nothing() =>
        new(null, [], null, new RuleMatchCounts(0, 0, 0), []);

    /// <summary>Null when either currency has no rate — a wrong number is worse than none.</summary>
    private static async Task<decimal?> EstimateAsync(
        IExchangeRateService fx, Transaction tx, string currency, CancellationToken ct) =>
        await fx.IsKnownAsync(currency, ct) && await fx.IsKnownAsync(tx.Currency, ct)
            ? await fx.ConvertAsync(Math.Abs(tx.Amount), tx.Currency, currency, ct)
            : null;

    /// <summary>
    /// Turns the request's correction into what gets stored on the withdrawal: both fields, or
    /// neither when the wallet received exactly what left the account.
    /// </summary>
    private static async Task<((string? Currency, decimal? Amount) Received, string? Error)> ResolveReceivedAsync(
        Transaction tx, UpdateTransactionRequest req, SkarbDbContext db, IExchangeRateService fx, CancellationToken ct)
    {
        var mirrored = tx.InternalSource == InternalSources.Cash && tx.Source != TransactionSources.Cash;
        if (!mirrored || req.IsInternal == false)
            return (default, "Only a withdrawal that was moved to a cash wallet can say what it paid out.");

        var currency = (req.CashCurrency ?? tx.Currency).Trim().ToUpperInvariant();
        if (currency.Length != 3 || !currency.All(char.IsAsciiLetter))
            return (default, "Currency must be a three-letter code, like EUR.");
        if (req.CashAmount is <= 0)
            return (default, "The amount you received has to be more than zero.");
        if (await db.Accounts.AnyAsync(a => a.IsCash && a.IsArchived && a.Currency == currency, ct))
            return (default, $"Your {currency} cash wallet is archived — unarchive it before moving cash there.");

        var sameCurrency = string.Equals(currency, tx.Currency, StringComparison.OrdinalIgnoreCase);
        var amount = req.CashAmount;
        if (amount is null && !sameCurrency)
        {
            // No figure given for another currency: freeze today's estimate. It is stored rather
            // than recomputed on read, because a ledger whose past drifts with the rate is wrong
            // every day in a new way.
            amount = await EstimateAsync(fx, tx, currency, ct);
            if (amount is null)
                return (default, $"There is no exchange rate for {currency} — enter the amount you received.");
        }

        // Same currency and the bank's own figure is no correction at all. Leaving the fields
        // empty keeps the wallet following the withdrawal if a hold settles differently.
        if (sameCurrency && (amount is null || amount == -tx.Amount)) return ((null, null), null);
        return ((currency, amount), null);
    }
}
