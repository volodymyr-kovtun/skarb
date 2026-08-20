using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Features.Categories;

public record UpsertCategoryRequest(string Name, string Emoji, string Color, string Kind);
public record CreateRuleRequest(string Pattern, Guid CategoryId, int? Priority, string? ApplyTo);
public record UpdateRuleRequest(Guid CategoryId, string? Pattern, string? ApplyTo);
public record RevertRuleRequest(List<RevertEntry> Entries);
public record RevertEntry(Guid TransactionId, Guid? PreviousCategoryId, string? PreviousSource);

public class CategoryEndpoints : IEndpointGroup
{
    private static readonly string[] ValidKinds =
        [CategoryKinds.Expense, CategoryKinds.Income, CategoryKinds.Investment];

    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/categories");

        group.MapGet("/", async (SkarbDbContext db) =>
            await db.Categories
                .OrderBy(c => c.Kind).ThenBy(c => c.Name)
                .Select(c => new
                {
                    c.Id, c.Name, c.Emoji, c.Color, c.Kind,
                    transactionCount = c.Transactions.Count,
                })
                .ToListAsync());

        group.MapPost("/", async (UpsertCategoryRequest req, SkarbDbContext db) =>
        {
            var error = Validate(req);
            if (error is not null) return Results.BadRequest(new { error });
            if (await db.Categories.AnyAsync(c => c.Name == req.Name.Trim()))
                return Results.BadRequest(new { error = "A category with this name already exists." });

            var cat = new Category
            {
                Name = req.Name.Trim(),
                Color = req.Color,
                Kind = req.Kind,
            };
            if (!string.IsNullOrWhiteSpace(req.Emoji)) cat.Emoji = req.Emoji.Trim();
            db.Categories.Add(cat);
            await db.SaveChangesAsync();
            return Results.Created($"/api/categories/{cat.Id}", cat.ToDto());
        });

        group.MapPatch("/{id:guid}", async (Guid id, UpsertCategoryRequest req, SkarbDbContext db) =>
        {
            var cat = await db.Categories.FindAsync(id);
            if (cat is null) return Results.NotFound();
            var error = Validate(req);
            if (error is not null) return Results.BadRequest(new { error });
            if (await db.Categories.AnyAsync(c => c.Name == req.Name.Trim() && c.Id != id))
                return Results.BadRequest(new { error = "A category with this name already exists." });

            cat.Name = req.Name.Trim();
            cat.Emoji = string.IsNullOrWhiteSpace(req.Emoji) ? cat.Emoji : req.Emoji.Trim();
            cat.Color = req.Color;
            cat.Kind = req.Kind;
            await db.SaveChangesAsync();
            return Results.Ok(cat.ToDto());
        });

        group.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db) =>
        {
            var cat = await db.Categories.FindAsync(id);
            if (cat is null) return Results.NotFound();
            db.Categories.Remove(cat); // transactions keep existing, becoming uncategorized (FK SetNull)
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        // ---------- categorization rules ----------
        var rules = app.MapGroup("/api/rules");

        rules.MapGet("/", async (SkarbDbContext db) =>
            await db.CategoryRules.Include(r => r.Category).OrderBy(r => r.Priority)
                .Select(r => new { r.Id, r.Pattern, r.Priority, category = r.Category!.ToDto() })
                .ToListAsync());

        // Creating the rule and re-filing the past are one decision the user made, so they are one
        // call — splitting them invites a half-applied state when the second half fails.
        rules.MapPost("/", async (CreateRuleRequest req, SkarbDbContext db, CancellationToken ct) =>
        {
            var pattern = req.Pattern?.Trim() ?? "";
            if (pattern.Length == 0) return Results.BadRequest(new { error = "Pattern is required." });
            if (!await db.Categories.AnyAsync(c => c.Id == req.CategoryId, ct))
                return Results.BadRequest(new { error = "Category not found." });

            // Saying the same thing twice should not produce two rules to maintain.
            var rule = await db.CategoryRules
                .FirstOrDefaultAsync(r => r.Pattern.ToLower() == pattern.ToLower() && r.CategoryId == req.CategoryId, ct);
            if (rule is null)
            {
                rule = new CategoryRule
                {
                    Pattern = pattern,
                    CategoryId = req.CategoryId,
                    Priority = req.Priority ?? await RuleApplication.NextPriorityAsync(db, ct),
                };
                db.CategoryRules.Add(rule);
            }

            var applied = await ApplyScopeAsync(db, pattern, req.CategoryId, req.ApplyTo, ct);
            await db.SaveChangesAsync(ct);
            return Results.Created($"/api/rules/{rule.Id}", new { rule.Id, applied = applied.Count, reverts = applied });
        });

        // Repointing the rule that already covers this keyword, rather than stacking a second one
        // beside it for the two to disagree over.
        rules.MapPatch("/{id:guid}", async (Guid id, UpdateRuleRequest req, SkarbDbContext db, CancellationToken ct) =>
        {
            var rule = await db.CategoryRules.FindAsync([id], ct);
            if (rule is null) return Results.NotFound();
            if (!await db.Categories.AnyAsync(c => c.Id == req.CategoryId, ct))
                return Results.BadRequest(new { error = "Category not found." });

            if (!string.IsNullOrWhiteSpace(req.Pattern)) rule.Pattern = req.Pattern.Trim();
            rule.CategoryId = req.CategoryId;
            // A corrected rule is a fresh decision, so it leads again.
            rule.Priority = await RuleApplication.NextPriorityAsync(db, ct);

            var applied = await ApplyScopeAsync(db, rule.Pattern, req.CategoryId, req.ApplyTo, ct);
            await db.SaveChangesAsync(ct);
            return Results.Ok(new { rule.Id, applied = applied.Count, reverts = applied });
        });

        // Undo for the toast that follows a bulk re-file. The client hands back exactly what the
        // apply reported, so no history has to be kept anywhere.
        rules.MapPost("/revert", async (RevertRuleRequest req, SkarbDbContext db, CancellationToken ct) =>
        {
            var ids = req.Entries.Select(e => e.TransactionId).ToList();
            var rows = await db.Transactions.Where(t => ids.Contains(t.Id)).ToDictionaryAsync(t => t.Id, ct);
            var reverted = 0;
            foreach (var entry in req.Entries)
            {
                if (!rows.TryGetValue(entry.TransactionId, out var tx)) continue;
                tx.CategoryId = entry.PreviousCategoryId;
                tx.CategorySource = entry.PreviousSource;
                reverted++;
            }
            await db.SaveChangesAsync(ct);
            return Results.Ok(new { reverted });
        });

        rules.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db) =>
        {
            var rule = await db.CategoryRules.FindAsync(id);
            if (rule is null) return Results.NotFound();
            db.CategoryRules.Remove(rule);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        // Re-run categorization over transactions that still have no category (e.g. after adding
        // rules). Only fills blanks, so nothing already filed — by hand or otherwise — is touched.
        rules.MapPost("/apply", async (SkarbDbContext db, ICategorizer categorizer, CancellationToken ct) =>
        {
            var pending = await db.Transactions
                .Where(t => t.CategoryId == null && !t.IsInternal)
                .ToListAsync(ct);
            var updated = 0;
            foreach (var t in pending)
            {
                var probe = new IncomingTransaction(t.ExternalId ?? t.Id.ToString(), t.Amount, t.Currency,
                    t.Description, t.OccurredAt, t.Source)
                { CounterParty = t.CounterParty, Mcc = t.Mcc, Note = t.Note, TypeCode = t.TypeCode };
                var verdict = await categorizer.ResolveAsync(probe, ct);
                if (verdict is null) continue;
                t.CategoryId = verdict.CategoryId;
                t.CategorySource = verdict.Source;
                updated++;
            }
            await db.SaveChangesAsync(ct);
            return Results.Ok(new { scanned = pending.Count, categorized = updated });
        });
    }

    /// <summary>
    /// Re-files the past according to the requested scope. Returns what changed, previous category
    /// and all, so the caller can hand the client an undo. Saving is left to the caller so the
    /// rule and its backfill land in one transaction.
    /// </summary>
    private static async Task<List<RuleApplication.Applied>> ApplyScopeAsync(
        SkarbDbContext db, string pattern, Guid categoryId, string? applyTo, CancellationToken ct)
    {
        var scope = applyTo ?? RuleScopes.None;
        if (scope == RuleScopes.None) return [];
        var matches = await RuleApplication.FindAsync(db, pattern, categoryId, ct);
        return RuleApplication.Apply(matches, categoryId, scope);
    }

    private static string? Validate(UpsertCategoryRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Name)) return "Name is required.";
        if (!ValidKinds.Contains(req.Kind)) return $"Kind must be one of: {string.Join(", ", ValidKinds)}.";
        return null;
    }
}
