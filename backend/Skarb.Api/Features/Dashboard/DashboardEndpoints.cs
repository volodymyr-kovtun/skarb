using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Dashboard;

public class DashboardEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        app.MapGet("/api/dashboard", async (SkarbDbContext db, IExchangeRateService fx, int months = 6) =>
        {
            var now = DateTime.UtcNow;
            var monthStart = new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);
            var prevMonthStart = monthStart.AddMonths(-1);
            var windowStart = monthStart.AddMonths(-(months - 1));

            // Net worth across accounts, converted to base currency.
            var accounts = await db.Accounts.Where(a => !a.IsArchived).OrderBy(a => a.CreatedAt).ToListAsync();
            var netWorth = 0m;
            var accountDtos = new List<object>();
            foreach (var a in accounts)
            {
                var converted = await fx.ToBaseAsync(a.Balance, a.Currency);
                netWorth += converted;
                accountDtos.Add(new { account = a.ToDto(), balanceBase = converted });
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

            async Task<(decimal income, decimal expense, decimal invested)> TotalsFor(int year, int month)
            {
                decimal income = 0, expense = 0, invested = 0;
                foreach (var row in flowRows.Where(r => r.Year == year && r.Month == month))
                {
                    var v = await fx.ToBaseAsync(Math.Abs(row.Sum), row.Currency);
                    if (row.IsInvestment) invested += row.IsIncome ? -v : v; // withdrawals reduce invested
                    else if (row.IsIncome) income += v;
                    else expense += v;
                }
                return (Math.Round(income, 2), Math.Round(expense, 2), Math.Round(invested, 2));
            }

            var cashflow = new List<object>();
            for (var m = 0; m < months; m++)
            {
                var d = windowStart.AddMonths(m);
                var (income, expense, invested) = await TotalsFor(d.Year, d.Month);
                cashflow.Add(new { month = d.ToString("yyyy-MM"), income, expense, invested });
            }

            var (curIncome, curExpense, curInvested) = await TotalsFor(monthStart.Year, monthStart.Month);
            var (prevIncome, prevExpense, prevInvested) = await TotalsFor(prevMonthStart.Year, prevMonthStart.Month);

            // All-time net contributions to investment-kind categories.
            var investedRows = await db.Transactions
                .Where(t => !t.IsExcluded && !t.IsInternal &&
                            t.Category != null && t.Category.Kind == CategoryKinds.Investment)
                .GroupBy(t => t.Currency)
                .Select(g => new { Currency = g.Key, Sum = g.Sum(t => t.Amount) })
                .ToListAsync();
            var allTimeInvested = 0m;
            foreach (var row in investedRows)
                allTimeInvested += await fx.ToBaseAsync(-row.Sum, row.Currency); // outgoing = positive contribution

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
                var v = await fx.ToBaseAsync(-row.Sum, row.Currency);
                byCategory[key] = byCategory.GetValueOrDefault(key) + v;
            }
            var spendingByCategory = byCategory
                .Select(kv => new
                {
                    categoryId = kv.Key == Guid.Empty ? (Guid?)null : kv.Key,
                    name = categories.TryGetValue(kv.Key, out var c) ? c.Name : "Uncategorized",
                    emoji = categories.TryGetValue(kv.Key, out var c2) ? c2.Emoji : "❔",
                    color = categories.TryGetValue(kv.Key, out var c3) ? c3.Color : "#CBD5E1",
                    amount = Math.Round(kv.Value, 2),
                })
                .OrderByDescending(x => x.amount)
                .ToList();

            var recent = await db.Transactions
                .Include(t => t.Account).Include(t => t.Category).Include(t => t.Tags)
                .OrderByDescending(t => t.OccurredAt).ThenByDescending(t => t.CreatedAt)
                .Take(8).ToListAsync();

            return new
            {
                baseCurrency = fx.BaseCurrency,
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
}
