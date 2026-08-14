using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Common.Services;

/// <summary>
/// Categorization strategy: user keyword rules first, then MCC (ISO 18245) mapping,
/// then a cautious income heuristic. Investment routing (e.g. "ibkr") is just a
/// seeded rule pointing at an investment-kind category — no special code path.
/// </summary>
public class RuleBasedCategorizer(SkarbDbContext db) : ICategorizer
{
    private static readonly (int From, int To, string Category)[] MccMap =
    [
        (5411, 5499, "Groceries"),
        (5811, 5814, "Restaurants & Cafes"),
        (4111, 4131, "Transport"),
        (5541, 5542, "Transport"),
        (7523, 7523, "Transport"),
        (5310, 5399, "Shopping"),
        (5611, 5699, "Shopping"),
        (5732, 5735, "Shopping"),
        (5940, 5949, "Shopping"),
        (4900, 4900, "Housing & Utilities"),
        (6513, 6513, "Housing & Utilities"),
        (4814, 4816, "Subscriptions"),
        (5968, 5968, "Subscriptions"),
        (7841, 7841, "Subscriptions"),
        (5912, 5912, "Health"),
        (8011, 8099, "Health"),
        (7832, 7832, "Entertainment"),
        (7911, 7999, "Entertainment"),
        (3000, 3999, "Travel"),
        (4511, 4511, "Travel"),
        (7011, 7011, "Travel"),
        (8211, 8299, "Education"),
        (6010, 6012, "Fees & Charges"),
        (6211, 6211, "Brokerage"),
        (6300, 6300, "Fees & Charges"),
    ];

    private List<CategoryRule>? _rules;
    private Dictionary<string, Guid>? _categoriesByName;

    public async Task<Guid?> ResolveAsync(string description, string? counterParty, int? mcc, decimal amount, CancellationToken ct)
    {
        var haystack = $"{description} {counterParty}".ToLowerInvariant();

        _rules ??= await db.CategoryRules.AsNoTracking().OrderBy(r => r.Priority).ToListAsync(ct);
        foreach (var rule in _rules)
        {
            if (!string.IsNullOrWhiteSpace(rule.Pattern) &&
                haystack.Contains(rule.Pattern.ToLowerInvariant()))
                return rule.CategoryId;
        }

        _categoriesByName ??= await db.Categories.AsNoTracking()
            .ToDictionaryAsync(c => c.Name, c => c.Id, ct);

        if (amount > 0)
        {
            // Only auto-tag small credits as cashback; large ones are left for the user (salary vs refund).
            if (amount < 50 && _categoriesByName.TryGetValue("Interest & Cashback", out var income))
                return income;
            return null;
        }

        if (mcc is int code)
        {
            foreach (var (from, to, name) in MccMap)
            {
                if (code >= from && code <= to && _categoriesByName.TryGetValue(name, out var id))
                    return id;
            }
        }

        return null;
    }
}
