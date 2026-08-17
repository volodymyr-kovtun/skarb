using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Common.Services;

/// <summary>
/// Categorization strategy: user keyword rules first, then MCC (ISO 18245) mapping,
/// then a cautious income heuristic. Investment routing (e.g. "ibkr") is just a
/// seeded rule pointing at an investment-kind category — no special code path.
/// MCC ranges target category SystemKeys, so renaming a category is safe.
/// </summary>
public class RuleBasedCategorizer(SkarbDbContext db) : ICategorizer
{
    private static readonly (int From, int To, string SystemKey)[] MccMap =
    [
        (5411, 5499, "groceries"),
        (5811, 5814, "restaurants"),
        (4111, 4131, "transport"),
        (5541, 5542, "transport"),
        (7523, 7523, "transport"),
        (5310, 5399, "shopping"),
        (5611, 5699, "shopping"),
        (5732, 5735, "shopping"),
        (5940, 5949, "shopping"),
        (4900, 4900, "housing"),
        (6513, 6513, "housing"),
        (4814, 4816, "subscriptions"),
        (5968, 5968, "subscriptions"),
        (7841, 7841, "subscriptions"),
        (5912, 5912, "health"),
        (8011, 8099, "health"),
        (7832, 7832, "entertainment"),
        (7911, 7999, "entertainment"),
        (3000, 3999, "travel"),
        (4511, 4511, "travel"),
        (7011, 7011, "travel"),
        (8211, 8299, "education"),
        (6010, 6012, "fees"),
        (6211, 6211, "brokerage"),
        (6300, 6300, "fees"),
    ];

    private List<CategoryRule>? _rules;
    private Dictionary<string, Guid>? _categoriesBySystemKey;

    public async Task<Guid?> ResolveAsync(string description, string? counterParty, int? mcc, decimal amount, CancellationToken ct)
    {
        var haystack = $"{description} {counterParty}";

        _rules ??= await db.CategoryRules.AsNoTracking().OrderBy(r => r.Priority).ToListAsync(ct);
        foreach (var rule in _rules)
        {
            if (!string.IsNullOrWhiteSpace(rule.Pattern) &&
                haystack.Contains(rule.Pattern, StringComparison.OrdinalIgnoreCase))
                return rule.CategoryId;
        }

        _categoriesBySystemKey ??= await db.Categories.AsNoTracking()
            .Where(c => c.SystemKey != null)
            .ToDictionaryAsync(c => c.SystemKey!, c => c.Id, ct);

        if (amount > 0)
        {
            // Only auto-tag small credits as cashback; large ones are left for the user (salary vs refund).
            if (amount < 50 && _categoriesBySystemKey.TryGetValue("interest-cashback", out var income))
                return income;
            return null;
        }

        if (mcc is int code)
        {
            foreach (var (from, to, key) in MccMap)
            {
                if (code >= from && code <= to && _categoriesBySystemKey.TryGetValue(key, out var id))
                    return id;
            }
        }

        return null;
    }
}
