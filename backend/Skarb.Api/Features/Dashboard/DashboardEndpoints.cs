using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Dashboard;

public class DashboardEndpoints : IEndpointGroup
{
    /// <summary>
    /// Always offered in the currency switcher, on top of the base currency and whatever
    /// the accounts themselves are held in.
    /// </summary>
    private static readonly string[] AlwaysOffered = ["PLN", "EUR", "USD"];

    public void Map(IEndpointRouteBuilder app)
    {
        app.MapGet("/api/dashboard", async (SkarbDbContext db, IExchangeRateService fx, string? currency, int months = 6) =>
        {
            var now = DateTime.UtcNow;
            var monthStart = new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);
            var prevMonthStart = monthStart.AddMonths(-1);
            // The window always covers the previous month too, so the summary tiles
            // can read from the same per-month totals as the chart.
            var windowStart = monthStart.AddMonths(-Math.Max(months - 1, 1));
            var chartStart = monthStart.AddMonths(-(months - 1));

            // Everything on this page is reported in one currency of the reader's choosing;
            // an unknown or missing request falls back to the configured base.
            var display = await ResolveCurrencyAsync(fx, currency);

            // Net worth across accounts, converted to the display currency.
            var accounts = await db.Accounts.Where(a => !a.IsArchived).OrderBy(a => a.CreatedAt).ToListAsync();
            var netWorth = 0m;
            var accountDtos = new List<object>();
            foreach (var a in accounts)
            {
                var converted = await fx.ConvertAsync(a.Balance, a.Currency, display);
                netWorth += converted;
                accountDtos.Add(new { account = a.ToDto(), balanceConverted = converted });
            }

            // Money flows grouped in SQL by month + currency + direction + investment-ness.
            // Internal transfers and manually excluded transactions never count.
            var flowRows = await db.Transactions
                .Where(t => !t.IsExcluded && !t.IsInternal && t.OccurredAt >= windowStart)
                .GroupBy(t => new
                {
                    t.OccurredAt.Year,
                    t.OccurredAt.Month,
                    t.Currency,
                    IsIncome = t.Amount > 0,
                    IsInvestment = t.Category != null && t.Category.Kind == CategoryKinds.Investment,
                })
                .Select(g => new
                {
                    g.Key.Year, g.Key.Month, g.Key.Currency, g.Key.IsIncome, g.Key.IsInvestment,
                    Sum = g.Sum(t => t.Amount),
                })
                .ToListAsync();

            // One conversion pass per month in the window; tiles and chart read the same numbers.
            var totalsByMonth = new Dictionary<DateTime, (decimal Income, decimal Expense, decimal Invested)>();
            for (var d = windowStart; d <= monthStart; d = d.AddMonths(1))
            {
                decimal income = 0, expense = 0, invested = 0;
                foreach (var row in flowRows.Where(r => r.Year == d.Year && r.Month == d.Month))
                {
                    var v = await fx.ConvertAsync(Math.Abs(row.Sum), row.Currency, display);
                    if (row.IsInvestment) invested += row.IsIncome ? -v : v; // withdrawals reduce invested
                    else if (row.IsIncome) income += v;
                    else expense += v;
                }
                totalsByMonth[d] = (Math.Round(income, 2), Math.Round(expense, 2), Math.Round(invested, 2));
            }

            var cashflow = new List<object>();
            for (var m = 0; m < months; m++)
            {
                var d = chartStart.AddMonths(m);
                var t = totalsByMonth.GetValueOrDefault(d);
                cashflow.Add(new { month = d.ToString("yyyy-MM"), income = t.Income, expense = t.Expense, invested = t.Invested });
            }

            var (curIncome, curExpense, curInvested) = totalsByMonth[monthStart];
            var (prevIncome, prevExpense, prevInvested) = totalsByMonth[prevMonthStart];

            // All-time net contributions to investment-kind categories.
            var investedRows = await db.Transactions
                .Where(t => !t.IsExcluded && !t.IsInternal &&
                            t.Category != null && t.Category.Kind == CategoryKinds.Investment)
                .GroupBy(t => t.Currency)
                .Select(g => new { Currency = g.Key, Sum = g.Sum(t => t.Amount) })
                .ToListAsync();
            var allTimeInvested = 0m;
            foreach (var row in investedRows)
                allTimeInvested += await fx.ConvertAsync(-row.Sum, row.Currency, display); // outgoing = positive contribution

            // Spending by category, current month (investments live in their own tile, not here).
            var catRows = await db.Transactions
                .Where(t => !t.IsExcluded && !t.IsInternal && t.Amount < 0 && t.OccurredAt >= monthStart &&
                            (t.Category == null || t.Category.Kind != CategoryKinds.Investment))
                .GroupBy(t => new { t.CategoryId, t.Currency })
                .Select(g => new { g.Key.CategoryId, g.Key.Currency, Sum = g.Sum(t => t.Amount) })
                .ToListAsync();
            var categories = await db.Categories.ToDictionaryAsync(c => c.Id);
            var byCategory = new Dictionary<Guid, decimal>(); // Guid.Empty = uncategorized
            foreach (var row in catRows)
            {
                var key = row.CategoryId ?? Guid.Empty;
                var v = await fx.ConvertAsync(-row.Sum, row.Currency, display);
                byCategory[key] = byCategory.GetValueOrDefault(key) + v;
            }
            var spendingByCategory = byCategory
                .Select(kv =>
                {
                    categories.TryGetValue(kv.Key, out var cat);
                    return new
                    {
                        categoryId = kv.Key == Guid.Empty ? (Guid?)null : kv.Key,
                        name = cat?.Name ?? "Uncategorized",
                        emoji = cat?.Emoji ?? "❔",
                        color = cat?.Color ?? "#CBD5E1",
                        amount = Math.Round(kv.Value, 2),
                    };
                })
                .OrderByDescending(x => x.amount)
                .ToList();

            var recent = await db.Transactions
                .Include(t => t.Account).Include(t => t.Category).Include(t => t.Tags)
                .OrderByDescending(t => t.OccurredAt).ThenByDescending(t => t.CreatedAt)
                .Take(8).ToListAsync();

            return new
            {
                currency = display,
                baseCurrency = fx.BaseCurrency,
                availableCurrencies = await AvailableCurrenciesAsync(fx, accounts),
                netWorth = Math.Round(netWorth, 2),
                accounts = accountDtos,
                month = new
                {
                    income = curIncome,
                    expense = curExpense,
                    invested = curInvested,
                    net = Math.Round(curIncome - curExpense - curInvested, 2),
                },
                prevMonth = new { income = prevIncome, expense = prevExpense, invested = prevInvested },
                allTimeInvested = Math.Round(allTimeInvested, 2),
                spendingByCategory,
                cashflow,
                recent = recent.Select(t => t.ToDto()),
            };
        });
    }

    /// <summary>Unknown or missing input falls back to the base currency, so a stale bookmark still renders.</summary>
    private static async Task<string> ResolveCurrencyAsync(IExchangeRateService fx, string? requested)
    {
        if (string.IsNullOrWhiteSpace(requested)) return fx.BaseCurrency;
        var code = requested.Trim().ToUpperInvariant();
        return code.Length == 3 && await fx.IsKnownAsync(code) ? code : fx.BaseCurrency;
    }

    /// <summary>What the currency switcher offers: base first, then the account currencies, then the majors.</summary>
    private static async Task<List<string>> AvailableCurrenciesAsync(IExchangeRateService fx, List<Account> accounts)
    {
        var codes = new List<string> { fx.BaseCurrency.ToUpperInvariant() };
        foreach (var raw in accounts.Select(a => a.Currency).Concat(AlwaysOffered))
        {
            var code = raw.ToUpperInvariant();
            if (!codes.Contains(code) && await fx.IsKnownAsync(code)) codes.Add(code);
        }
        return codes;
    }
}
