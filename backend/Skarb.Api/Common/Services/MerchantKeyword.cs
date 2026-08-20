namespace Skarb.Api.Common.Services;

/// <summary>
/// Turns a bank descriptor into the keyword a <see cref="Domain.CategoryRule"/> should match on.
/// A descriptor is not a merchant name: "JMP S.A. BIEDRONKA 7184" names a holding company, a shop
/// and a till, and only the middle part identifies the place you keep going back to.
/// </summary>
/// <remarks>
/// Card rows have already been through <c>EnableBankingProvider.CleanCardMerchant</c> by the time
/// they are stored, so the city prefix and country suffix are gone and this only has to do the
/// merchant-key part. Trimming happens at the ends only, never from the middle, so whatever comes
/// out is still a contiguous run of the descriptor and therefore still matches the row it came
/// from. The guess is never final either: it is shown in an editable field with a live match
/// count, and <see cref="Suggestion.Alternatives"/> offers back what was trimmed off.
/// </remarks>
public static class MerchantKeyword
{
    /// <param name="Keyword">Null when nothing usable could be derived — the user types their own.</param>
    /// <param name="Alternatives">Wider readings of the same descriptor, best first.</param>
    public sealed record Suggestion(string? Keyword, IReadOnlyList<string> Alternatives);

    /// <summary>
    /// Company-form tokens. Safe to drop when they trail a name ("orlen s.a.", "kowalski sp. z o.o.").
    /// </summary>
    private static readonly HashSet<string> TrailingLegalForms = new(StringComparer.OrdinalIgnoreCase)
    {
        "s.a.", "sa", "sp.", "sp", "z", "o.o.", "o.o", "zoo", "spółka", "spolka", "sp.j.", "j.",
        "s.c.", "sc", "llc", "l.l.c.", "inc", "inc.", "ltd", "ltd.", "gmbh", "b.v.", "bv", "nv",
        "oy", "ab", "as", "a/s", "srl", "s.r.l.", "spa", "plc", "kg", "ag",
    };

    /// <summary>
    /// The unambiguous half of the set above. A holding company in front of a brand
    /// ("JMP S.A. BIEDRONKA") is only cut on one of these — never on "z", "as" or "ab",
    /// which are ordinary words in the middle of a Polish or English name.
    /// </summary>
    private static readonly HashSet<string> LeadingLegalForms = new(StringComparer.OrdinalIgnoreCase)
    {
        "s.a.", "sa", "o.o.", "sp.j.", "s.c.", "llc", "l.l.c.", "gmbh", "ltd", "ltd.",
        "inc", "inc.", "b.v.", "plc", "srl",
    };

    /// <summary>
    /// Words that name a <em>kind</em> of business rather than a business, so "PIEKARNIA BAKER'S
    /// HOUSE" is really "baker's house". Only stripped from the front, and only while something
    /// identifying survives behind them.
    /// </summary>
    private static readonly HashSet<string> TradeWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "piekarnia", "cukiernia", "apteka", "restauracja", "kawiarnia", "pizzeria", "sklep",
        "market", "supermarket", "delikatesy", "hotel", "salon", "stacja", "przychodnia",
        "gabinet", "centrum", "biuro", "firma", "ph", "phu", "pphu", "fhu", "zpu", "pw",
    };

    /// <summary>
    /// A keyword made only of these says nothing about who was paid — every transfer in the
    /// account carries them. Better to offer nothing than a rule that files half the ledger.
    /// </summary>
    private static readonly HashSet<string> StopWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "przelew", "przelewy", "wychodzący", "wychodzacy", "przychodzący", "przychodzacy",
        "na", "do", "od", "za", "rachunek", "rachunku", "numer", "tytułem", "tytulem",
        "własny", "wlasny", "płatność", "platnosc", "płatności", "platnosci", "zakup",
        "zakupy", "blik", "iko", "transfer", "payment", "purchase", "card", "return",
        "mobile", "web", "internet", "online", "wpłata", "wplata", "wypłata", "wyplata",
        "gotówki", "gotowki", "in", "out", "c2c", "standard", "instant", "e-commerce",
    };

    private const int MaxWords = 4;
    private const int MaxLength = 40;
    private const int MinLength = 3;
    /// <summary>How deep into the descriptor a holding-company marker is still believable.</summary>
    private const int LeadingScan = 3;

    /// <summary>
    /// Derives the keyword for a stored transaction. The other fields come along because the
    /// result is checked against the row it was derived from before being offered.
    /// </summary>
    public static Suggestion For(string description, string? counterParty, string? note, string? typeCode)
    {
        // A transfer names a real party in its own field; a card row only has the descriptor.
        var raw = string.IsNullOrWhiteSpace(counterParty) ? description : counterParty;
        var whole = Collapse(raw);
        if (whole.Length == 0) return new Suggestion(null, []);

        // Card processors glue a product onto the merchant ("ANTHROPIC* CLAUDE SUB");
        // everything after the star varies per charge, so the merchant is what precedes it.
        var star = whole.IndexOf('*');
        var full = star >= MinLength ? whole[..star].TrimEnd() : whole;
        var trimmed = Trim(full);
        var haystack = RuleBasedCategorizer.Haystack(description, counterParty, note, typeCode);

        // Best first, then progressively less trimmed. Anything that does not fire on its own
        // source row is a derivation bug, not a suggestion — drop it rather than ship it.
        var candidates = new List<string>();
        foreach (var candidate in new[] { trimmed, full, whole, FirstWord(full) })
        {
            if (candidate.Length < MinLength || candidates.Contains(candidate)) continue;
            if (StopWordsOnly(candidate)) continue;
            if (!RuleBasedCategorizer.RuleHits(haystack, typeCode, candidate)) continue;
            candidates.Add(candidate);
        }

        return candidates.Count == 0
            ? new Suggestion(null, [])
            : new Suggestion(candidates[0], candidates.Skip(1).ToList());
    }

    /// <summary>Lowercased and single-spaced, so a keyword reads like the seeded ones.</summary>
    private static string Collapse(string value) =>
        string.Join(' ', value.ToLowerInvariant()
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));

    private static string FirstWord(string collapsed)
    {
        var word = collapsed.Split(' ')[0];
        return word.Length >= MinLength ? word : "";
    }

    private static string Trim(string collapsed)
    {
        var words = collapsed.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToList();

        // Trailing noise: till numbers ("biedronka 7184") and company forms ("orlen s.a.").
        while (words.Count > 1 && (words[^1].All(char.IsDigit) || TrailingLegalForms.Contains(words[^1])))
            words.RemoveAt(words.Count - 1);

        // A holding company in front of the brand: cut through the last company-form token
        // that is still near the front, as long as a name is left behind it.
        var cut = -1;
        for (var i = 0; i < Math.Min(LeadingScan, words.Count - 1); i++)
            if (LeadingLegalForms.Contains(words[i])) cut = i;
        if (cut >= 0) words.RemoveRange(0, cut + 1);

        // A leading trade word, but only while something identifying is left behind it.
        while (words.Count > 1 && TradeWords.Contains(words[0]))
            words.RemoveAt(0);

        if (words.Count > MaxWords) words = words[..MaxWords];

        var result = string.Join(' ', words);
        if (result.Length > MaxLength)
        {
            result = result[..MaxLength];
            var lastSpace = result.LastIndexOf(' ');
            if (lastSpace >= MinLength) result = result[..lastSpace];
        }
        return result.Length >= MinLength ? result : "";
    }

    /// <summary>True when every word is boilerplate or a bare number.</summary>
    private static bool StopWordsOnly(string keyword)
    {
        var words = keyword.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return words.Length == 0 || words.All(w => StopWords.Contains(w) || w.All(char.IsDigit));
    }
}
