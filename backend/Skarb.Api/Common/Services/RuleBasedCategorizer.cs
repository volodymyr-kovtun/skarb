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
        (8398, 8398, "donations"),
        (6010, 6012, "fees"),
        (6211, 6211, "brokerage"),
        (6300, 6300, "fees"),
    ];

    private List<(string Pattern, Guid CategoryId, string Kind)>? _rules;
    private Dictionary<string, Guid>? _categoriesBySystemKey;

    public async Task<Guid?> ResolveAsync(IncomingTransaction item, CancellationToken ct)
    {
        var (description, counterParty, mcc, amount) = (item.Description, item.CounterParty, item.Mcc, item.Amount);
        // Rules match against description, counterparty, the raw bank note and the type code,
        // so "FEE" or "CARD-ATM" can be targeted even when the description is a merchant name.
        var haystack = $"{description} {counterParty} {item.Note} {item.TypeCode}";

        _rules ??= await db.CategoryRules.AsNoTracking()
            .OrderBy(r => r.Priority)
            .Select(r => new ValueTuple<string, Guid, string>(r.Pattern, r.CategoryId, r.Category!.Kind))
            .ToListAsync(ct);
        // Card-terminal descriptors arrive glued together ("WARSZAWAFOUNDATIONCOFFEE.PL",
        // "mesGymBeamSK"), so word boundaries can't be trusted there — fall back to substring
        // matching for card rows; everything else (transfers, notes) gets whole-word matching.
        var isCardRow = item.TypeCode?.StartsWith("CARD", StringComparison.OrdinalIgnoreCase) ?? false;

        foreach (var (pattern, categoryId, kind) in _rules)
        {
            // A rule only applies in the direction its category describes: income categories to
            // money in, spending/investment categories to money out. Prevents "zwrot" (refund) on an
            // outgoing repayment or "salary"-like words on an outgoing transfer from misfiring.
            var directionOk = kind == CategoryKinds.Income ? amount > 0 : amount < 0;
            if (!directionOk || string.IsNullOrWhiteSpace(pattern)) continue;
            var hit = isCardRow
                ? haystack.Contains(pattern, StringComparison.OrdinalIgnoreCase)
                : Matches(haystack, pattern);
            if (hit) return categoryId;
        }

        _categoriesBySystemKey ??= await db.Categories.AsNoTracking()
            .Where(c => c.SystemKey != null)
            .ToDictionaryAsync(c => c.SystemKey!, c => c.Id, ct);

        if (amount > 0)
        {
            // Genuine person-to-person rails (BLIK phone transfers etc.) are gifts/repayments, not cashback.
            // A plain named-counterparty bank transfer could equally be an employer or a client, so
            // that is left for the user to classify once (then a keyword rule covers the future).
            var isP2P = (item.TypeCode?.Contains("C2C", StringComparison.OrdinalIgnoreCase) ?? false) ||
                        (item.TypeCode?.Contains("MOBILE-PAYMENT", StringComparison.OrdinalIgnoreCase) ?? false);
            if (isP2P && _categoriesBySystemKey.TryGetValue("transfers-in", out var fromPeople))
                return fromPeople;
            // Small anonymous credits (card cashback, interest) — large ones stay for the user (salary vs refund).
            var anonymous = string.IsNullOrWhiteSpace(counterParty) && !isP2P;
            if (amount < 50 && anonymous && _categoriesBySystemKey.TryGetValue("interest-cashback", out var income))
                return income;
            return null;
        }

        // Outgoing money over person-to-person rails (BLIK phone transfers etc.).
        var outP2P = (item.TypeCode?.Contains("C2C", StringComparison.OrdinalIgnoreCase) ?? false) ||
                     (item.TypeCode?.Contains("MOBILE-PAYMENT", StringComparison.OrdinalIgnoreCase) ?? false);
        if (outP2P && _categoriesBySystemKey.TryGetValue("transfers-out", out var toPeople))
            return toPeople;

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

    /// <summary>
    /// Case-insensitive match that respects word boundaries at the pattern's alphanumeric edges,
    /// so "zus" hits "ZUS" but not "consultZUSA", while "apple.com/bill" or "-fee" still work
    /// as plain substrings on their punctuation edges.
    /// </summary>
    internal static bool Matches(string haystack, string pattern)
    {
        var idx = 0;
        while ((idx = haystack.IndexOf(pattern, idx, StringComparison.OrdinalIgnoreCase)) >= 0)
        {
            var before = idx == 0 ? ' ' : haystack[idx - 1];
            var after = idx + pattern.Length >= haystack.Length ? ' ' : haystack[idx + pattern.Length];
            var leftOk = !char.IsLetterOrDigit(pattern[0]) || !char.IsLetterOrDigit(before);
            var rightOk = !char.IsLetterOrDigit(pattern[^1]) || !char.IsLetterOrDigit(after);
            if (leftOk && rightOk) return true;
            idx++;
        }
        return false;
    }
}
