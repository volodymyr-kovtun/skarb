using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Features.Dashboard;

public class DashboardEndpoints : IEndpointGroup
{
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
            var display = await DisplayCurrency.ResolveAsync(fx, currency);

            // Net worth across accounts, converted to the display currency. Archived accounts are
            // closed and excluded ones are deliberately not counted, so neither reaches this page —
            // and neither does anything below, which all reads through OnCountedAccounts().
            var accounts = await db.Accounts.Where(a => !a.IsArchived && !a.IsExcluded)
                .OrderBy(a => a.CreatedAt).ToListAsync();
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
                .OnCountedAccounts()
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
                .OnCountedAccounts()
                .Where(t => !t.IsExcluded && !t.IsInternal &&
                            t.Category != null && t.Category.Kind == CategoryKinds.Investment)
                .GroupBy(t => t.Currency)
                .Select(g => new { Currency = g.Key, Sum = g.Sum(t => t.Amount) })
                .ToListAsync();
            var allTimeInvested = 0m;
            foreach (var row in investedRows)
                allTimeInvested += await fx.ConvertAsync(-row.Sum, row.Currency, display); // outgoing = positive contribution

            // Everything the month counts as spending — investments live in their own tile,
            // not here. All three breakdowns below read from this one definition.
            var monthSpending = db.Transactions
                .OnCountedAccounts()
                .Where(t => !t.IsExcluded && !t.IsInternal && t.Amount < 0 && t.OccurredAt >= monthStart &&
                            (t.Category == null || t.Category.Kind != CategoryKinds.Investment));

            // Spending by category, current month.
            var catRows = await monthSpending
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

            // Spending by account, current month — the same money, cut by where it left from.
            // Like categories, these partition the month — a transaction sits on exactly one account.
            var accountRows = await monthSpending
                .GroupBy(t => new { t.AccountId, t.Currency })
                .Select(g => new { g.Key.AccountId, g.Key.Currency, Sum = g.Sum(t => t.Amount) })
                .ToListAsync();
            var byAccount = new Dictionary<Guid, decimal>();
            foreach (var row in accountRows)
            {
                var v = await fx.ConvertAsync(-row.Sum, row.Currency, display);
                byAccount[row.AccountId] = byAccount.GetValueOrDefault(row.AccountId) + v;
            }
            // The accounts loaded above are exactly the counted ones this spending is narrowed to,
            // so a row that cannot be named would mean the two disagreed — drop it rather than throw.
            var accountsById = accounts.ToDictionary(a => a.Id);
            var spendingByAccount = byAccount
                .Where(kv => accountsById.ContainsKey(kv.Key))
                .Select(kv => new
                {
                    accountId = kv.Key,
                    name = accountsById[kv.Key].Name,
                    bank = accountsById[kv.Key].Bank,
                    color = accountsById[kv.Key].Color,
                    amount = Math.Round(kv.Value, 2),
                })
                .OrderByDescending(x => x.amount)
                .ToList();

            // Spending by tag, current month. A transaction wearing two tags counts under both,
            // so these do not partition the month the way categories do — multiTagCount says how
            // often that actually happens, and the UI owns up to it when it does.
            var tagRows = await monthSpending
                .SelectMany(t => t.Tags, (t, tag) => new { tag.Id, tag.Name, tag.Color, t.Currency, t.Amount })
                .GroupBy(x => new { x.Id, x.Name, x.Color, x.Currency })
                .Select(g => new { g.Key.Id, g.Key.Name, g.Key.Color, g.Key.Currency, Sum = g.Sum(x => x.Amount) })
                .ToListAsync();
            var byTag = new Dictionary<Guid, (string Name, string Color, decimal Amount)>();
            foreach (var row in tagRows)
            {
                var v = await fx.ConvertAsync(-row.Sum, row.Currency, display);
                var t = byTag.GetValueOrDefault(row.Id);
                byTag[row.Id] = (row.Name, row.Color, t.Amount + v);
            }
            var spendingByTag = byTag
                .Select(kv => new { tagId = kv.Key, name = kv.Value.Name, color = kv.Value.Color, amount = Math.Round(kv.Value.Amount, 2) })
                .OrderByDescending(x => x.amount)
                .ToList();

            // What carries no tag at all — the honest remainder next to the tags above.
            var untaggedRows = await monthSpending
                .Where(t => !t.Tags.Any())
                .GroupBy(t => t.Currency)
                .Select(g => new { Currency = g.Key, Sum = g.Sum(t => t.Amount) })
                .ToListAsync();
            var untaggedSpending = 0m;
            foreach (var row in untaggedRows)
                untaggedSpending += await fx.ConvertAsync(-row.Sum, row.Currency, display);

            var multiTagCount = await monthSpending.CountAsync(t => t.Tags.Count > 1);

            var recent = await db.Transactions
                .OnCountedAccounts()
                .Include(t => t.Account).Include(t => t.Category).Include(t => t.Tags)
                .OrderByDescending(t => t.OccurredAt).ThenByDescending(t => t.CreatedAt)
                .Take(8).ToListAsync();

            return new
            {
                currency = display,
                baseCurrency = fx.BaseCurrency,
                availableCurrencies = await DisplayCurrency.OptionsAsync(fx, accounts.Select(a => a.Currency)),
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
                spendingByAccount,
                spendingByTag,
                untaggedSpending = Math.Round(untaggedSpending, 2),
                multiTagCount,
                cashflow,
                recent = recent.Select(t => t.ToDto()),
            };
        });
    }
}
