using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Persistence;

public static class Seed
{
    public static async Task EnsureSeededAsync(SkarbDbContext db)
    {
        if (await db.Categories.AnyAsync()) return;

        var categories = new (string Name, string Emoji, string Color, string Kind)[]
        {
            ("Groceries", "🛒", "#22C55E", CategoryKinds.Expense),
            ("Restaurants & Cafes", "🍜", "#F97316", CategoryKinds.Expense),
            ("Transport", "🚕", "#3B82F6", CategoryKinds.Expense),
            ("Shopping", "🛍️", "#EC4899", CategoryKinds.Expense),
            ("Housing & Utilities", "🏠", "#8B5CF6", CategoryKinds.Expense),
            ("Subscriptions", "📺", "#06B6D4", CategoryKinds.Expense),
            ("Health", "💊", "#EF4444", CategoryKinds.Expense),
            ("Entertainment", "🎟️", "#EAB308", CategoryKinds.Expense),
            ("Travel", "✈️", "#14B8A6", CategoryKinds.Expense),
            ("Education", "📚", "#6366F1", CategoryKinds.Expense),
            ("Fees & Charges", "🏦", "#94A3B8", CategoryKinds.Expense),
            ("Other", "🧩", "#64748B", CategoryKinds.Expense),
            ("Salary", "💼", "#10B981", CategoryKinds.Income),
            ("Freelance", "🧑‍💻", "#84CC16", CategoryKinds.Income),
            ("Interest & Cashback", "💰", "#F59E0B", CategoryKinds.Income),
            ("Brokerage", "📈", "#B45309", CategoryKinds.Investment),
            ("Crypto", "🪙", "#A16207", CategoryKinds.Investment),
        };

        db.Categories.AddRange(categories.Select(c => new Category
        {
            Name = c.Name, Emoji = c.Emoji, Color = c.Color, Kind = c.Kind
        }));
        await db.SaveChangesAsync();

        // Out-of-the-box rules for common investment destinations (user-editable).
        var brokerage = await db.Categories.FirstAsync(c => c.Name == "Brokerage");
        db.CategoryRules.AddRange(
            new CategoryRule { Pattern = "interactive brokers", CategoryId = brokerage.Id, Priority = 1 },
            new CategoryRule { Pattern = "ibkr", CategoryId = brokerage.Id, Priority = 2 });

        db.Tags.AddRange(
            new Tag { Name = "vacation", Color = "#14B8A6" },
            new Tag { Name = "work", Color = "#6366F1" },
            new Tag { Name = "family", Color = "#F97316" });

        await db.SaveChangesAsync();
    }
}
