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

public record UpdateTransactionRequest(
    string? Description, decimal? Amount, DateTime? OccurredAt, string? Note,
    bool? IsExcluded, bool? IsInternal, bool CategorySet, Guid? CategoryId, List<Guid>? TagIds);

public class TransactionEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/transactions");

        group.MapGet("/", async (
            SkarbDbContext db,
            Guid? accountId, Guid? categoryId, Guid[]? tagIds, string? search,
            DateTime? from, DateTime? to, bool? uncategorized, bool? internalOnly, bool? investmentsOnly,
            bool? hideInternal, int page = 1, int pageSize = 50) =>
        {
            var q = db.Transactions
                .Include(t => t.Account).Include(t => t.Category).Include(t => t.Tags)
                .AsQueryable();

            // Excluded and archived accounts are out of the picture, so their transactions stay out
            // of the list too. Naming one in the account filter is the deliberate way back in.
            if (accountId is Guid a) q = q.Where(t => t.AccountId == a);
            else q = q.OnCountedAccounts();
            if (categoryId is Guid c) q = q.Where(t => t.CategoryId == c);
            // Several tags read as "any of these" — narrowing to transactions carrying all of
            // them would return almost nothing, since a transaction rarely wears two labels.
            if (tagIds is { Length: > 0 }) q = q.Where(t => t.Tags.Any(x => tagIds.Contains(x.Id)));
            if (uncategorized == true) q = q.Where(t => t.CategoryId == null && !t.IsInternal);
            if (internalOnly == true) q = q.Where(t => t.IsInternal);
            // Transfers between the owner's own accounts are noise once you're reading the
            // list as a spending log, so they can be dropped without touching any other filter.
            else if (hideInternal == true) q = q.Where(t => !t.IsInternal);
            if (investmentsOnly == true) q = q.Where(t => t.Category != null && t.Category.Kind == CategoryKinds.Investment);
            if (from is DateTime f) q = q.Where(t => t.OccurredAt >= DateTime.SpecifyKind(f, DateTimeKind.Utc));
            if (to is DateTime to_) q = q.Where(t => t.OccurredAt < DateTime.SpecifyKind(to_, DateTimeKind.Utc).AddDays(1));
            if (!string.IsNullOrWhiteSpace(search))
            {
                var s = $"%{search}%";
                q = q.Where(t =>
                    EF.Functions.ILike(t.Description, s) ||
                    (t.CounterParty != null && EF.Functions.ILike(t.CounterParty, s)) ||
                    (t.Note != null && EF.Functions.ILike(t.Note, s)));
            }

            var total = await q.CountAsync();
            var items = await q.OrderByDescending(t => t.OccurredAt).ThenByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize).Take(pageSize)
                .ToListAsync();
            return new PagedResult<TransactionDto>(items.Select(t => t.ToDto()).ToList(), total, page, pageSize);
        });

        group.MapPost("/", async (
            CreateTransactionRequest req, SkarbDbContext db, ICategorizer categorizer, CancellationToken ct) =>
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
            await ManualAccountBalance.RecomputeAsync(db, account);

            await db.Entry(tx).Reference(t => t.Account).LoadAsync();
            await db.Entry(tx).Reference(t => t.Category).LoadAsync();
            return Results.Created($"/api/transactions/{tx.Id}", tx.ToDto());
        });

        group.MapPatch("/{id:guid}", async (Guid id, UpdateTransactionRequest req, SkarbDbContext db) =>
        {
            var tx = await db.Transactions
                .Include(t => t.Account).Include(t => t.Category).Include(t => t.Tags)
                .FirstOrDefaultAsync(t => t.Id == id);
            if (tx is null) return Results.NotFound();

            if (req.Description is not null) tx.Description = req.Description;
            if (req.Note is not null) tx.Note = req.Note.Length == 0 ? null : req.Note;
            if (req.IsExcluded is bool excl) tx.IsExcluded = excl;
            if (req.OccurredAt is DateTime occ) tx.OccurredAt = DateTime.SpecifyKind(occ, DateTimeKind.Utc);
            if (req.Amount is decimal amount && tx.Source == TransactionSources.Manual)
                tx.Amount = amount;
            // Choosing a category by hand is a decision, so it is recorded as one: a later bulk
            // re-file steps around it. Clearing it back to uncategorized decides nothing.
            if (req.CategorySet)
            {
                tx.CategoryId = req.CategoryId;
                tx.CategorySource = req.CategoryId is null ? null : CategorySources.Manual;
            }
            if (req.TagIds is not null)
                tx.Tags = await db.Tags.Where(t => req.TagIds.Contains(t.Id)).ToListAsync();

            if (req.IsInternal is bool isInternal && isInternal != tx.IsInternal)
            {
                // Un-marking one leg of a detected pair releases both. Both are stamped manual:
                // without that they look untouched to the detector, which pairs them straight
                // back up on the next sync.
                if (!isInternal && tx.TransferGroupId is Guid groupId)
                {
                    var legs = await db.Transactions.Where(t => t.TransferGroupId == groupId).ToListAsync();
                    foreach (var leg in legs)
                    {
                        leg.IsInternal = false;
                        leg.TransferGroupId = null;
                        leg.InternalSource = InternalSources.Manual;
                    }
                }
                else
                {
                    tx.IsInternal = isInternal;
                    tx.InternalSource = InternalSources.Manual;
                }
            }

            await db.SaveChangesAsync();
            if (tx.Account is not null) await ManualAccountBalance.RecomputeAsync(db, tx.Account);
            await db.Entry(tx).Reference(t => t.Category).LoadAsync();
            return Results.Ok(tx.ToDto());
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

        group.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db) =>
        {
            var tx = await db.Transactions.Include(t => t.Account).FirstOrDefaultAsync(t => t.Id == id);
            if (tx is null) return Results.NotFound();
            db.Transactions.Remove(tx);
            await db.SaveChangesAsync();
            if (tx.Account is not null) await ManualAccountBalance.RecomputeAsync(db, tx.Account);
            return Results.NoContent();
        });
    }

    /// <summary>How many matching transactions the offer sheet shows as evidence for its count.</summary>
    private const int SampleSize = 3;

    /// <summary>A null pattern is how the API says "do not offer anything here".</summary>
    private static RuleSuggestionResponse Nothing() =>
        new(null, [], null, new RuleMatchCounts(0, 0, 0), []);
}
