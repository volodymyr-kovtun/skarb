using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Features.Tags;

public record CreateTagRequest(string Name, string? Color);
public record UpdateTagRequest(string? Name, string? Color);

public class TagEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/tags");

        // What each tag actually cost over a period. Money out, money in and investment
        // contributions are kept apart exactly as the dashboard keeps them, so "spent"
        // means the same thing on both pages.
        group.MapGet("/summary", async (
            SkarbDbContext db, IExchangeRateService fx, string? currency, DateTime? from, DateTime? to) =>
        {
            var display = await DisplayCurrency.ResolveAsync(fx, currency);

            var inPeriod = db.Transactions.Where(t => !t.IsExcluded && !t.IsInternal);
            if (from is DateTime f) inPeriod = inPeriod.Where(t => t.OccurredAt >= DateTime.SpecifyKind(f, DateTimeKind.Utc));
            if (to is DateTime t2) inPeriod = inPeriod.Where(t => t.OccurredAt < DateTime.SpecifyKind(t2, DateTimeKind.Utc).AddDays(1));

            // One row per tag + currency + direction + investment-ness. A transaction wearing
            // two tags lands in both their groups, which is what per-tag totals should do —
            // it also means the tag totals do not add up to the period's spending.
            var rows = await inPeriod
                .SelectMany(t => t.Tags, (t, tag) => new
                {
                    TagId = tag.Id,
                    t.Currency,
                    t.Amount,
                    IsInvestment = t.Category != null && t.Category.Kind == CategoryKinds.Investment,
                })
                .GroupBy(x => new { x.TagId, x.Currency, IsIncome = x.Amount > 0, x.IsInvestment })
                .Select(g => new
                {
                    g.Key.TagId, g.Key.Currency, g.Key.IsIncome, g.Key.IsInvestment,
                    Sum = g.Sum(x => x.Amount),
                    Count = g.Count(),
                })
                .ToListAsync();

            var totals = new Dictionary<Guid, TagTotals>();
            foreach (var row in rows)
            {
                var v = await fx.ConvertAsync(Math.Abs(row.Sum), row.Currency, display);
                var t = totals.GetValueOrDefault(row.TagId);
                if (row.IsInvestment) t.Invested += row.IsIncome ? -v : v; // withdrawals reduce invested
                else if (row.IsIncome) t.Earned += v;
                else t.Spent += v;
                t.Count += row.Count;
                totals[row.TagId] = t;
            }

            // Unused tags stay in the list: seeing a tag at zero is how you notice it went unused.
            var tags = await db.Tags.OrderBy(t => t.Name).ToListAsync();
            var items = tags
                .Select(tag =>
                {
                    var t = totals.GetValueOrDefault(tag.Id);
                    return new
                    {
                        tag = tag.ToDto(),
                        spent = Math.Round(t.Spent, 2),
                        earned = Math.Round(t.Earned, 2),
                        invested = Math.Round(t.Invested, 2),
                        transactionCount = t.Count,
                    };
                })
                .OrderByDescending(x => x.spent)
                .ThenByDescending(x => x.transactionCount)
                .ThenBy(x => x.tag.Name)
                .ToList();

            // How much of the period's spending carries no tag at all — the honest denominator
            // for reading the numbers above.
            var untaggedRows = await inPeriod
                .Where(t => !t.Tags.Any() && t.Amount < 0 &&
                            (t.Category == null || t.Category.Kind != CategoryKinds.Investment))
                .GroupBy(t => t.Currency)
                .Select(g => new { Currency = g.Key, Sum = g.Sum(t => t.Amount), Count = g.Count() })
                .ToListAsync();
            var untaggedSpent = 0m;
            foreach (var row in untaggedRows)
                untaggedSpent += await fx.ConvertAsync(-row.Sum, row.Currency, display);

            var held = await db.Accounts.Where(a => !a.IsArchived).Select(a => a.Currency).Distinct().ToListAsync();

            return new
            {
                currency = display,
                availableCurrencies = await DisplayCurrency.OptionsAsync(fx, held),
                tags = items,
                untagged = new { spent = Math.Round(untaggedSpent, 2), transactionCount = untaggedRows.Sum(r => r.Count) },
            };
        });

        group.MapPost("/", async (CreateTagRequest req, SkarbDbContext db) =>
        {
            var name = req.Name.Trim().ToLowerInvariant();
            if (name.Length == 0) return Results.BadRequest(new { error = "Name is required." });
            var existing = await db.Tags.FirstOrDefaultAsync(t => t.Name == name);
            if (existing is not null) return Results.Ok(existing.ToDto());
            var tag = new Tag { Name = name };
            if (req.Color is not null) tag.Color = req.Color;
            db.Tags.Add(tag);
            await db.SaveChangesAsync();
            return Results.Created($"/api/tags/{tag.Id}", tag.ToDto());
        });

        group.MapPatch("/{id:guid}", async (Guid id, UpdateTagRequest req, SkarbDbContext db) =>
        {
            var tag = await db.Tags.FindAsync(id);
            if (tag is null) return Results.NotFound();

            if (req.Name is not null)
            {
                var name = req.Name.Trim().ToLowerInvariant();
                if (name.Length == 0) return Results.BadRequest(new { error = "Name is required." });
                if (await db.Tags.AnyAsync(t => t.Id != id && t.Name == name))
                    return Results.BadRequest(new { error = $"A tag called \"{name}\" already exists." });
                tag.Name = name;
            }
            if (req.Color is not null) tag.Color = req.Color;

            await db.SaveChangesAsync();
            return Results.Ok(tag.ToDto());
        });

        group.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db) =>
        {
            var tag = await db.Tags.FindAsync(id);
            if (tag is null) return Results.NotFound();
            db.Tags.Remove(tag);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });
    }

    /// <summary>Running totals per tag while the per-currency rows are converted one by one.</summary>
    private record struct TagTotals(decimal Spent, decimal Earned, decimal Invested, int Count);
}
