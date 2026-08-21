namespace Skarb.Api.Common.Services;

/// <summary>
/// The stretch of time a report answers for, and the equally long stretch it is measured against.
/// Ranges are half-open — <c>Start</c> counts, <c>End</c> does not — so a month-to-date window and
/// the month that follows it can never claim the same day twice.
/// </summary>
public readonly record struct ReportPeriod(
    string Key, DateTime Start, DateTime End, DateTime PreviousStart, DateTime PreviousEnd)
{
    /// <summary>Calendar months the window touches — what a per-month chart needs to cover it.</summary>
    public int MonthSpan
    {
        get
        {
            // End is exclusive, so the last month it reaches is the one the final instant sits in.
            var last = End.AddTicks(-1);
            return ((last.Year - Start.Year) * 12) + last.Month - Start.Month + 1;
        }
    }

    /// <summary>Every window a report may be asked for. The first is what an unknown request falls back to.</summary>
    public static readonly string[] Keys = ["month", "last", "3m", "6m", "ytd"];

    /// <summary>Unknown or missing input falls back to the current month, so a stale bookmark still renders.</summary>
    public static string Normalize(string? requested)
    {
        var key = requested?.Trim().ToLowerInvariant();
        return key is not null && Keys.Contains(key) ? key : Keys[0];
    }

    public static ReportPeriod Resolve(string? requested, DateTime now)
    {
        var key = Normalize(requested);
        var monthStart = new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);
        // Money that moved today belongs to today, so a window reaching "now" runs to midnight.
        var todayEnd = now.Date.AddDays(1);

        var (start, end, shift) = key switch
        {
            "last" => (monthStart.AddMonths(-1), monthStart, 1),
            "3m" => (monthStart.AddMonths(-2), todayEnd, 3),
            "6m" => (monthStart.AddMonths(-5), todayEnd, 6),
            "ytd" => (new DateTime(now.Year, 1, 1, 0, 0, 0, DateTimeKind.Utc), todayEnd, 12),
            _ => (monthStart, todayEnd, 1),
        };

        // The comparison always sits one whole period back on the calendar. How much of it counts
        // depends on whether this window has finished: a window still running is measured against
        // only as much of the earlier one as has elapsed — 21 days into August against the first 21
        // days of July, not against all 31 — while one that has closed on a month boundary is
        // measured against the whole span before it. The clamp keeps a month-to-date that has run
        // longer than the month it is compared against from bleeding past it.
        var previousStart = start.AddMonths(-shift);
        var previousEnd = end == todayEnd ? previousStart + (end - start) : start;
        if (previousEnd > start) previousEnd = start;

        return new ReportPeriod(key, start, end, previousStart, previousEnd);
    }
}
