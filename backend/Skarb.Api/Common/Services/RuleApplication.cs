using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Common.Services;

/// <summary>How far back a rule reaches over transactions that already exist.</summary>
public static class RuleScopes
{
    /// <summary>Only new transactions from here on. The rule is saved and nothing is rewritten.</summary>
    public const string None = "none";
    /// <summary>Rows nothing decided, plus rows a rule, MCC or heuristic filed — a guess this supersedes.</summary>
    public const string Automatic = "automatic";
    /// <summary>Also rows the user filed by hand, and rows from before provenance was recorded.</summary>
    public const string All = "all";
}

/// <summary>
/// Finds the transactions a keyword rule would file, and files them. Every match here goes
/// through <see cref="RuleBasedCategorizer"/>'s own hit test, so a preview cannot promise rows
/// that ingest would then treat differently.
/// </summary>
public static class RuleApplication
{
    /// <summary>Rows a rule would change, split by how much of a decision the current category was.</summary>
    /// <param name="Untouched">
    /// Matches the user filed by hand, or filed before provenance was recorded. Left alone unless
    /// the scope is <see cref="RuleScopes.All"/>.
    /// </param>
    public sealed record Matches(
        List<Transaction> Uncategorized,
        List<Transaction> Automatic,
        List<Transaction> Untouched)
    {
        /// <summary>The rows a given scope would rewrite, newest first.</summary>
        public IEnumerable<Transaction> InScope(string scope) => scope switch
        {
            RuleScopes.All => Uncategorized.Concat(Automatic).Concat(Untouched),
            RuleScopes.Automatic => Uncategorized.Concat(Automatic),
            _ => [],
        };
    }

    /// <summary>One rewritten row and what it was filed as before, so the change can be undone.</summary>
    public sealed record Applied(Guid TransactionId, Guid? PreviousCategoryId, string? PreviousSource);

    /// <summary>
    /// Everything the pattern would file into <paramref name="categoryId"/>. Rows already in that
    /// category are left out — re-filing them would change nothing and inflate every count.
    /// </summary>
    public static async Task<Matches> FindAsync(
        SkarbDbContext db, string pattern, Guid categoryId, CancellationToken ct)
    {
        var kind = await db.Categories.Where(c => c.Id == categoryId)
            .Select(c => c.Kind).FirstOrDefaultAsync(ct) ?? CategoryKinds.Expense;

        // A wide net in SQL, narrowed in memory by the real matcher. The pattern is a literal, so
        // its LIKE metacharacters are escaped — an unescaped backslash would quietly drop rows the
        // exact pass never gets to see. The net is per-column, so a pattern that only matches
        // across the seam between two fields is missed: that is an artifact of concatenating them,
        // not a merchant anyone typed.
        var like = $"%{EscapeLiteral(pattern)}%";
        var candidates = await db.Transactions
            .Include(t => t.Account).Include(t => t.Category)
            .Where(t => !t.IsInternal && t.CategoryId != categoryId)
            .Where(t => EF.Functions.ILike(t.Description, like, EscapeChar)
                        || (t.CounterParty != null && EF.Functions.ILike(t.CounterParty, like, EscapeChar))
                        || (t.Note != null && EF.Functions.ILike(t.Note, like, EscapeChar))
                        || (t.TypeCode != null && EF.Functions.ILike(t.TypeCode, like, EscapeChar)))
            .OrderByDescending(t => t.OccurredAt).ThenByDescending(t => t.CreatedAt)
            .ToListAsync(ct);

        var matches = new Matches([], [], []);
        foreach (var t in candidates)
        {
            if (!RuleBasedCategorizer.DirectionAllows(kind, t.Amount)) continue;
            var haystack = RuleBasedCategorizer.Haystack(t.Description, t.CounterParty, t.Note, t.TypeCode);
            if (!RuleBasedCategorizer.RuleHits(haystack, t.TypeCode, pattern)) continue;

            if (t.CategoryId is null) matches.Uncategorized.Add(t);
            else if (IsAutomatic(t.CategorySource)) matches.Automatic.Add(t);
            else matches.Untouched.Add(t);
        }
        return matches;
    }

    /// <summary>
    /// Files every in-scope match into the category. Returns what changed and what it was before,
    /// which is the whole of the undo story — no history table needed.
    /// </summary>
    public static List<Applied> Apply(Matches matches, Guid categoryId, string scope)
    {
        var applied = new List<Applied>();
        foreach (var t in matches.InScope(scope))
        {
            applied.Add(new Applied(t.Id, t.CategoryId, t.CategorySource));
            t.CategoryId = categoryId;
            t.CategorySource = CategorySources.Rule;
        }
        return applied;
    }

    private const string EscapeChar = "\\";

    /// <summary>Makes a keyword safe to drop inside a LIKE pattern as plain text.</summary>
    private static string EscapeLiteral(string value) =>
        value.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_");

    /// <summary>
    /// A category no-one chose deliberately: a keyword rule, the MCC map, or the categorizer's
    /// own fallbacks. Null means provenance was never recorded, which is read as "might have
    /// been the user" and left alone.
    /// </summary>
    private static bool IsAutomatic(string? source) =>
        source is CategorySources.Rule or CategorySources.Mcc or CategorySources.Heuristic;

    /// <summary>
    /// A hand-written rule has to beat the ~200 seeded ones, and lower priority is evaluated
    /// first — so it sorts one ahead of whatever currently leads, walking into negatives as
    /// corrections accumulate. The newest correction winning is the right default when the same
    /// merchant is corrected twice.
    /// </summary>
    public static async Task<int> NextPriorityAsync(SkarbDbContext db, CancellationToken ct = default)
    {
        var lowest = await db.CategoryRules.Select(r => (int?)r.Priority).MinAsync(ct);
        return (lowest ?? 1) - 1;
    }
}
