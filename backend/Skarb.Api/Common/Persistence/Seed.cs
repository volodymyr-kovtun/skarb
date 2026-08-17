using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Persistence;

public static class Seed
{
    // (SystemKey, Name, Emoji, Color, Kind) — SystemKey is the stable id MCC mapping targets.
    private static readonly (string Key, string Name, string Emoji, string Color, string Kind)[] Defaults =
    [
        ("groceries", "Groceries", "🛒", "#22C55E", CategoryKinds.Expense),
        ("restaurants", "Restaurants & Cafes", "🍜", "#F97316", CategoryKinds.Expense),
        ("transport", "Transport", "🚕", "#3B82F6", CategoryKinds.Expense),
        ("shopping", "Shopping", "🛍️", "#EC4899", CategoryKinds.Expense),
        ("housing", "Housing & Utilities", "🏠", "#8B5CF6", CategoryKinds.Expense),
        ("subscriptions", "Subscriptions", "📺", "#06B6D4", CategoryKinds.Expense),
        ("health", "Health", "💊", "#EF4444", CategoryKinds.Expense),
        ("entertainment", "Entertainment", "🎟️", "#EAB308", CategoryKinds.Expense),
        ("travel", "Travel", "✈️", "#14B8A6", CategoryKinds.Expense),
        ("education", "Education", "📚", "#6366F1", CategoryKinds.Expense),
        ("fees", "Fees & Charges", "🏦", "#94A3B8", CategoryKinds.Expense),
        ("other", "Other", "🧩", "#64748B", CategoryKinds.Expense),
        ("salary", "Salary", "💼", "#10B981", CategoryKinds.Income),
        ("freelance", "Freelance", "🧑‍💻", "#84CC16", CategoryKinds.Income),
        ("interest-cashback", "Interest & Cashback", "💰", "#F59E0B", CategoryKinds.Income),
        ("brokerage", "Brokerage", "📈", "#B45309", CategoryKinds.Investment),
        ("crypto", "Crypto", "🪙", "#A16207", CategoryKinds.Investment),
    ];

    public static async Task EnsureSeededAsync(SkarbDbContext db)
    {
        if (await db.Categories.AnyAsync())
        {
            await BackfillSystemKeysAsync(db);
            return;
        }

        db.Categories.AddRange(Defaults.Select(c => new Category
        {
            SystemKey = c.Key, Name = c.Name, Emoji = c.Emoji, Color = c.Color, Kind = c.Kind
        }));
        await db.SaveChangesAsync();

        // Out-of-the-box rules for common investment destinations (user-editable).
        var brokerage = await db.Categories.FirstAsync(c => c.SystemKey == "brokerage");
        db.CategoryRules.AddRange(
            new CategoryRule { Pattern = "interactive brokers", CategoryId = brokerage.Id, Priority = 1 },
            new CategoryRule { Pattern = "ibkr", CategoryId = brokerage.Id, Priority = 2 });

        db.Tags.AddRange(
            new Tag { Name = "vacation", Color = "#14B8A6" },
            new Tag { Name = "work", Color = "#6366F1" },
            new Tag { Name = "family", Color = "#F97316" });

        await db.SaveChangesAsync();
    }

    /// <summary>Assigns system keys to pre-existing databases seeded before the column existed.</summary>
    private static async Task BackfillSystemKeysAsync(SkarbDbContext db)
    {
        var unkeyed = await db.Categories.Where(c => c.SystemKey == null).ToListAsync();
        if (unkeyed.Count == 0) return;
        var byName = Defaults.ToDictionary(d => d.Name, d => d.Key);
        foreach (var cat in unkeyed)
        {
            if (byName.TryGetValue(cat.Name, out var key)) cat.SystemKey = key;
        }
        await db.SaveChangesAsync();
    }
}
