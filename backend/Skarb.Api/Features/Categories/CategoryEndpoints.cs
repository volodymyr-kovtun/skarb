using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Features.Categories;

public record UpsertCategoryRequest(string Name, string Emoji, string Color, string Kind);
public record CreateRuleRequest(string Pattern, Guid CategoryId, int Priority);

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

        rules.MapPost("/", async (CreateRuleRequest req, SkarbDbContext db) =>
        {
            if (string.IsNullOrWhiteSpace(req.Pattern))
                return Results.BadRequest(new { error = "Pattern is required." });
            var rule = new CategoryRule { Pattern = req.Pattern.Trim(), CategoryId = req.CategoryId, Priority = req.Priority };
            db.CategoryRules.Add(rule);
            await db.SaveChangesAsync();
            return Results.Created($"/api/rules/{rule.Id}", new { rule.Id });
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
        // rules). Never overrides a category the user set by hand — only fills blanks.
        rules.MapPost("/apply", async (SkarbDbContext db, ICategorizer categorizer) =>
        {
            var pending = await db.Transactions
                .Where(t => t.CategoryId == null && !t.IsInternal)
                .ToListAsync();
            var updated = 0;
            foreach (var t in pending)
            {
                var probe = new IncomingTransaction(t.ExternalId ?? t.Id.ToString(), t.Amount, t.Currency,
                    t.Description, t.OccurredAt, t.Source)
                { CounterParty = t.CounterParty, Mcc = t.Mcc, Note = t.Note };
                var cat = await categorizer.ResolveAsync(probe, CancellationToken.None);
                if (cat is null) continue;
                t.CategoryId = cat;
                updated++;
            }
            await db.SaveChangesAsync();
            return Results.Ok(new { scanned = pending.Count, categorized = updated });
        });
    }

    private static string? Validate(UpsertCategoryRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Name)) return "Name is required.";
        if (!ValidKinds.Contains(req.Kind)) return $"Kind must be one of: {string.Join(", ", ValidKinds)}.";
        return null;
    }
}
