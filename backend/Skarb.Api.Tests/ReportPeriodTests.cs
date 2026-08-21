using Skarb.Api.Common.Services;

namespace Skarb.Api.Tests;

/// <summary>
/// Which days a dashboard window covers, and which days it is measured against. The comparison
/// is the delicate half: a month-to-date read against a whole previous month reports a collapse
/// in spending on every day but the last one.
/// </summary>
public class ReportPeriodTests
{
    // Mid-afternoon on the 21st — three weeks into a 31-day month.
    private static readonly DateTime Now = new(2026, 8, 21, 14, 30, 0, DateTimeKind.Utc);

    private static DateTime Utc(int y, int m, int d) => new(y, m, d, 0, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Month_to_date_runs_from_the_first_through_the_end_of_today()
    {
        var p = ReportPeriod.Resolve("month", Now);

        Assert.Equal(Utc(2026, 8, 1), p.Start);
        // Half-open: everything that moved today counts, nothing tomorrow does.
        Assert.Equal(Utc(2026, 8, 22), p.End);
    }

    [Fact]
    public void Month_to_date_is_compared_against_the_same_days_of_last_month()
    {
        var p = ReportPeriod.Resolve("month", Now);

        Assert.Equal(Utc(2026, 7, 1), p.PreviousStart);
        Assert.Equal(Utc(2026, 7, 22), p.PreviousEnd);
        // Twenty-one days either side, so the percentages underneath compare like with like.
        Assert.Equal(p.End - p.Start, p.PreviousEnd - p.PreviousStart);
    }

    [Fact]
    public void A_month_to_date_longer_than_the_month_behind_it_stops_at_that_month()
    {
        // All 31 days of March against February, which has only 28 — without the clamp the
        // comparison would reach into March and count some of the same days twice.
        var p = ReportPeriod.Resolve("month", new DateTime(2026, 3, 31, 9, 0, 0, DateTimeKind.Utc));

        Assert.Equal(Utc(2026, 2, 1), p.PreviousStart);
        Assert.Equal(Utc(2026, 3, 1), p.PreviousEnd);
    }

    [Fact]
    public void Last_month_is_a_closed_month_compared_against_the_whole_month_before_it()
    {
        var p = ReportPeriod.Resolve("last", Now);

        Assert.Equal(Utc(2026, 7, 1), p.Start);
        Assert.Equal(Utc(2026, 8, 1), p.End);
        // June is shorter than July, and a finished month is still compared whole.
        Assert.Equal(Utc(2026, 6, 1), p.PreviousStart);
        Assert.Equal(Utc(2026, 7, 1), p.PreviousEnd);
    }

    [Fact]
    public void Multi_month_windows_end_today_and_are_compared_over_the_same_elapsed_span()
    {
        var p = ReportPeriod.Resolve("3m", Now);

        Assert.Equal(Utc(2026, 6, 1), p.Start);
        Assert.Equal(Utc(2026, 8, 22), p.End);
        Assert.Equal(Utc(2026, 3, 1), p.PreviousStart);
        Assert.Equal(p.End - p.Start, p.PreviousEnd - p.PreviousStart);
    }

    [Fact]
    public void Six_months_reaches_back_across_the_year_boundary()
    {
        var p = ReportPeriod.Resolve("6m", Now);

        Assert.Equal(Utc(2026, 3, 1), p.Start);
        Assert.Equal(Utc(2025, 9, 1), p.PreviousStart);
    }

    [Fact]
    public void Year_to_date_is_compared_against_the_same_stretch_of_last_year()
    {
        var p = ReportPeriod.Resolve("ytd", Now);

        Assert.Equal(Utc(2026, 1, 1), p.Start);
        Assert.Equal(Utc(2026, 8, 22), p.End);
        Assert.Equal(Utc(2025, 1, 1), p.PreviousStart);
        Assert.Equal(Utc(2025, 8, 22), p.PreviousEnd);
    }

    [Theory]
    [InlineData("month", 1)]
    [InlineData("last", 1)]
    [InlineData("3m", 3)]
    [InlineData("6m", 6)]
    [InlineData("ytd", 8)] // January through August
    public void Month_span_counts_the_calendar_months_the_window_touches(string key, int expected)
    {
        Assert.Equal(expected, ReportPeriod.Resolve(key, Now).MonthSpan);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData("all-time")]
    public void An_unknown_or_missing_window_falls_back_to_this_month(string? requested)
    {
        var p = ReportPeriod.Resolve(requested, Now);

        Assert.Equal("month", p.Key);
        Assert.Equal(Utc(2026, 8, 1), p.Start);
    }

    [Theory]
    [InlineData("YTD", "ytd")]
    [InlineData(" 6M ", "6m")]
    public void Casing_and_padding_are_forgiven(string requested, string expected)
    {
        Assert.Equal(expected, ReportPeriod.Resolve(requested, Now).Key);
    }
}
