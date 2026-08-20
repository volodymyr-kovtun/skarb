using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Persistence;

public static class Seed
{
    // (SystemKey, Name, Emoji, Color, Kind) — SystemKey is the stable id MCC mapping targets.
    private static readonly (string Key, string Name, string Emoji, string Color, string Kind)[] Defaults =
    [
        ("groceries", "Groceries", "🛒", "#426F50", CategoryKinds.Expense),
        ("restaurants", "Restaurants & Cafes", "🍜", "#9F4B25", CategoryKinds.Expense),
        ("transport", "Transport", "🚕", "#546783", CategoryKinds.Expense),
        ("shopping", "Shopping", "🛍️", "#974D6E", CategoryKinds.Expense),
        ("housing", "Housing & Utilities", "🏠", "#775B88", CategoryKinds.Expense),
        ("subscriptions", "Subscriptions", "📺", "#456D67", CategoryKinds.Expense),
        ("health", "Health", "💊", "#B0322A", CategoryKinds.Expense),
        ("entertainment", "Entertainment", "🎟️", "#7B6230", CategoryKinds.Expense),
        ("travel", "Travel", "✈️", "#2F7168", CategoryKinds.Expense),
        ("education", "Education", "📚", "#5A5F9E", CategoryKinds.Expense),
        ("fees", "Fees & Charges", "🏦", "#91897C", CategoryKinds.Expense),
        ("cash", "Cash", "💵", "#6B6559", CategoryKinds.Expense),
        ("taxes", "Taxes & Insurance", "🏛️", "#6A4B8F", CategoryKinds.Expense),
        ("transfers-out", "Transfers to people", "🤝", "#8A8375", CategoryKinds.Expense),
        ("other", "Other", "🧩", "#6E6A5E", CategoryKinds.Expense),
        ("salary", "Salary", "💼", "#3F7A5C", CategoryKinds.Income),
        ("freelance", "Freelance", "🧑‍💻", "#6B7A38", CategoryKinds.Income),
        ("interest-cashback", "Interest & Cashback", "💰", "#A06A24", CategoryKinds.Income),
        ("transfers-in", "Transfers from people", "🎁", "#47806A", CategoryKinds.Income),
        ("refunds", "Refunds", "↩️", "#2F7168", CategoryKinds.Income),
        ("brokerage", "Brokerage", "📈", "#8A4A20", CategoryKinds.Investment),
        ("crypto", "Crypto", "🪙", "#7A5A2A", CategoryKinds.Investment),
    ];

    // (Pattern, SystemKey, Priority) — case-insensitive "contains" match on description, counterparty,
    // bank note and bank type code. Tuned for the Polish market + common global merchants; the
    // user can edit or delete any of these in Categories → rules.
    private static readonly (string Pattern, string Key, int Priority)[] DefaultRules =
    [
        // investments
        ("interactive brokers", "brokerage", 1), ("ibkr", "brokerage", 2), ("ib llc", "brokerage", 3),
        ("xtb", "brokerage", 4), ("degiro", "brokerage", 5), ("revolut trading", "brokerage", 6),
        ("binance", "crypto", 7), ("coinbase", "crypto", 8), ("kraken", "crypto", 9),
        // taxes / insurance
        ("urząd skarbowy", "taxes", 20), ("urzad skarbowy", "taxes", 21), ("zus", "taxes", 22),
        ("pzu", "taxes", 23), ("nfz", "taxes", 24), ("podatek", "taxes", 25),
        // bank fees / cash (matched via PKO type codes and descriptions)
        ("card-atm", "cash", 30), ("bankomat", "cash", 31), ("wypłata gotówki", "cash", 32),
        ("opłata za", "fees", 35), ("prowizja", "fees", 36), ("fee", "fees", 37),
        // groceries
        ("biedronka", "groceries", 50), ("żabka", "groceries", 51), ("zabka", "groceries", 52),
        ("lidl", "groceries", 53), ("auchan", "groceries", 54), ("carrefour", "groceries", 55),
        ("kaufland", "groceries", 56), ("netto", "groceries", 57), ("dino", "groceries", 58),
        ("stokrotka", "groceries", 59), ("aldi", "groceries", 60), ("frisco", "groceries", 61),
        ("lewiatan", "groceries", 62), ("delikatesy", "groceries", 63), ("supermarket", "groceries", 64),
        // housing & utilities
        ("wspólnota mieszkaniowa", "housing", 70), ("wspolnota mieszkaniowa", "housing", 71),
        ("czynsz", "housing", 72), ("spółdzielnia", "housing", 73), ("e.on", "housing", 74),
        ("pge", "housing", 75), ("tauron", "housing", 76), ("enea", "housing", 77), ("innogy", "housing", 78),
        ("pgnig", "housing", 79), ("veolia", "housing", 80), ("mpwik", "housing", 81), ("ikea", "housing", 82),
        // telecom / subscriptions
        ("orange", "subscriptions", 90), ("play", "subscriptions", 91), ("p4 sp", "subscriptions", 92),
        ("t-mobile", "subscriptions", 93), ("plus gsm", "subscriptions", 94), ("polkomtel", "subscriptions", 95),
        ("upc", "subscriptions", 96), ("netia", "subscriptions", 97), ("vectra", "subscriptions", 98),
        ("netflix", "subscriptions", 100), ("spotify", "subscriptions", 101), ("apple.com/bill", "subscriptions", 102),
        ("youtube", "subscriptions", 103), ("hbo", "subscriptions", 104), ("disney", "subscriptions", 105),
        ("anthropic", "subscriptions", 106), ("openai", "subscriptions", 107), ("chatgpt", "subscriptions", 108),
        ("github", "subscriptions", 109), ("jetbrains", "subscriptions", 110), ("digitalocean", "subscriptions", 111),
        ("google", "subscriptions", 112), ("google storage", "subscriptions", 113), ("icloud", "subscriptions", 114),
        ("microsoft", "subscriptions", 115), ("adobe", "subscriptions", 116), ("notion", "subscriptions", 117),
        // transport
        ("uber", "transport", 130), ("bolt", "transport", 131), ("freenow", "transport", 132), ("free now", "transport", 133),
        ("jakdojade", "transport", 134), ("ztm", "transport", 135), ("mpk", "transport", 136), ("koleo", "transport", 137),
        ("pkp intercity", "transport", 138), ("polregio", "transport", 139), ("orlen", "transport", 140),
        ("bp", "transport", 141), ("shell", "transport", 142), ("circle k", "transport", 143), ("moya", "transport", 144),
        ("parking", "transport", 145), ("spp", "transport", 146), ("veturilo", "transport", 147), ("lime", "transport", 148),
        // restaurants & cafes
        ("restauracja", "restaurants", 160), ("restaurant", "restaurants", 159), ("pizza", "restaurants", 161), ("pizzeria", "restaurants", 178), ("kebab", "restaurants", 162),
        ("mcdonald", "restaurants", 163), ("kfc", "restaurants", 164), ("burger", "restaurants", 165),
        ("starbucks", "restaurants", 166), ("costa coffee", "restaurants", 167), ("coffee", "restaurants", 168),
        ("cafe", "restaurants", 169), ("kawiarnia", "restaurants", 170), ("bar", "restaurants", 171),
        ("pyszne", "restaurants", 172), ("glovo", "restaurants", 173), ("wolt", "restaurants", 174),
        ("uber eats", "restaurants", 175), ("sushi", "restaurants", 176), ("bistro", "restaurants", 177),
        // shopping
        ("allegro", "shopping", 190), ("amazon", "shopping", 191), ("zalando", "shopping", 192),
        ("rossmann", "shopping", 193), ("hebe", "shopping", 194), ("empik", "shopping", 195),
        ("media markt", "shopping", 196), ("mediamarkt", "shopping", 197), ("rtv euro", "shopping", 198),
        ("x-kom", "shopping", 199), ("decathlon", "shopping", 200), ("h&m", "shopping", 201),
        ("zara", "shopping", 202), ("reserved", "shopping", 203), ("sinsay", "shopping", 204),
        ("pepco", "shopping", 205), ("action", "shopping", 206), ("leroy merlin", "shopping", 207),
        ("castorama", "shopping", 208), ("obi", "shopping", 209), ("temu", "shopping", 210), ("aliexpress", "shopping", 211),
        ("apple store", "shopping", 212), ("kwiatowy", "shopping", 213), ("kwiaciarnia", "shopping", 214),
        // health
        ("apteka", "health", 230), ("gemini", "health", 231), ("dr.max", "health", 232), ("doz", "health", 233),
        ("medicover", "health", 234), ("luxmed", "health", 235), ("lux med", "health", 236), ("enel-med", "health", 237),
        ("dentysta", "health", 238), ("stomatolog", "health", 239), ("przychodnia", "health", 240),
        ("gymbeam", "health", 241), ("multisport", "health", 242), ("fitness", "health", 243), ("siłownia", "health", 244),
        // entertainment
        ("multikino", "entertainment", 260), ("cinema city", "entertainment", 261), ("helios", "entertainment", 262),
        ("kino", "entertainment", 263), ("cinema", "entertainment", 269), ("steam", "entertainment", 264), ("playstation", "entertainment", 265),
        ("nintendo", "entertainment", 266), ("eventim", "entertainment", 267), ("ticketmaster", "entertainment", 268),
        // travel
        ("ryanair", "travel", 280), ("wizz", "travel", 281), ("lot polish", "travel", 282), ("lufthansa", "travel", 283),
        ("booking.com", "travel", 284), ("airbnb", "travel", 285), ("hotel", "travel", 286), ("hostel", "travel", 287),
        ("flixbus", "travel", 288), ("esky", "travel", 289), ("skyscanner", "travel", 290),
        // education
        ("udemy", "education", 300), ("coursera", "education", 301), ("pluralsight", "education", 302),
        ("duolingo", "education", 303), ("szkoła", "education", 304), ("kurs", "education", 305),
        // income
        ("wynagrodzenie", "salary", 320), ("salary", "salary", 321), ("pensja", "salary", 322),
        ("card-payment-return", "refunds", 330), ("zwrot", "refunds", 331), ("refund", "refunds", 332),
    ];

    // Default patterns from earlier versions that were replaced above (substring-era rules that
    // misfire under whole-word matching). Removed on startup so old databases converge.
    private static readonly string[] RetiredDefaultPatterns =
        ["restaura", "pizz", "bp ", "play ", "pge ", "obi ", "doz ", "spp ", "bar ", "-fee", " fee", "google *",
         "mobile-payment-c2c", "blik"];

    public static async Task EnsureSeededAsync(SkarbDbContext db)
    {
        if (await db.Categories.AnyAsync())
        {
            await BackfillSystemKeysAsync(db);
            await AddMissingDefaultsAsync(db);
            return;
        }

        db.Categories.AddRange(Defaults.Select(c => new Category
        {
            SystemKey = c.Key, Name = c.Name, Emoji = c.Emoji, Color = c.Color, Kind = c.Kind
        }));
        await db.SaveChangesAsync();

        await AddMissingDefaultsAsync(db);

        db.Tags.AddRange(
            new Tag { Name = "vacation", Color = "#2F7168" },
            new Tag { Name = "work", Color = "#5A5F9E" },
            new Tag { Name = "family", Color = "#9F4B25" });

        await db.SaveChangesAsync();
    }

    /// <summary>
    /// Adds default categories/rules that don't exist yet. Rules are keyed by pattern, so a
    /// user who deleted one on purpose won't get it back only if they also keep a rule with
    /// the same pattern — acceptable for a personal tool; edit the table above to tune.
    /// </summary>
    private static async Task AddMissingDefaultsAsync(SkarbDbContext db)
    {
        var byKey = await db.Categories.Where(c => c.SystemKey != null).ToDictionaryAsync(c => c.SystemKey!);
        foreach (var d in Defaults)
        {
            if (byKey.ContainsKey(d.Key)) continue;
            var cat = new Category { SystemKey = d.Key, Name = d.Name, Emoji = d.Emoji, Color = d.Color, Kind = d.Kind };
            db.Categories.Add(cat);
            byKey[d.Key] = cat;
        }
        await db.SaveChangesAsync();

        var retired = await db.CategoryRules.Where(r => RetiredDefaultPatterns.Contains(r.Pattern)).ToListAsync();
        if (retired.Count > 0) { db.CategoryRules.RemoveRange(retired); await db.SaveChangesAsync(); }

        var existingPatterns = (await db.CategoryRules.Select(r => r.Pattern).ToListAsync())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var (pattern, key, priority) in DefaultRules)
        {
            if (existingPatterns.Contains(pattern) || !byKey.TryGetValue(key, out var cat)) continue;
            db.CategoryRules.Add(new CategoryRule { Pattern = pattern, CategoryId = cat.Id, Priority = priority });
        }
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
