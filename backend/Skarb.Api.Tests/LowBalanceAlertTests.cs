using Skarb.Api.Common.Domain;
using Skarb.Api.Features.Notifications;

namespace Skarb.Api.Tests;

/// <summary>
/// The alerting policy: announce a drop below the threshold once, remind daily while it
/// stays low, re-arm on recovery — so a balance hovering near the limit can't spam the
/// person who tops the account up.
/// </summary>
public class LowBalanceAlertTests
{
    private static readonly DateTime Now = new(2026, 8, 20, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void No_threshold_means_no_alert_no_matter_the_balance()
    {
        Assert.Equal(LowBalanceCall.None, LowBalanceAlerter.Evaluate(null, -1000m, null, Now));
        Assert.Equal(LowBalanceCall.None, LowBalanceAlerter.Evaluate(null, -1000m, Now.AddDays(-3), Now));
    }

    [Fact]
    public void Dropping_below_the_threshold_alerts_once()
    {
        Assert.Equal(LowBalanceCall.Send, LowBalanceAlerter.Evaluate(5000m, 4999.99m, null, Now));
        // The latch set by that send keeps the next checks quiet.
        Assert.Equal(LowBalanceCall.None, LowBalanceAlerter.Evaluate(5000m, 4200m, Now.AddMinutes(-30), Now));
    }

    [Fact]
    public void Exactly_at_the_threshold_is_not_low()
    {
        // "Less than 5000" is the contract — 5000 itself is still fine.
        Assert.Equal(LowBalanceCall.None, LowBalanceAlerter.Evaluate(5000m, 5000m, null, Now));
    }

    [Fact]
    public void Recovery_rearms_so_the_next_drop_is_announced_again()
    {
        Assert.Equal(LowBalanceCall.Rearm, LowBalanceAlerter.Evaluate(5000m, 6000m, Now.AddHours(-2), Now));
        Assert.Equal(LowBalanceCall.Rearm, LowBalanceAlerter.Evaluate(5000m, 5000m, Now.AddHours(-2), Now));
        // Nothing to re-arm when nothing was sent.
        Assert.Equal(LowBalanceCall.None, LowBalanceAlerter.Evaluate(5000m, 6000m, null, Now));
    }

    [Fact]
    public void Still_low_a_day_later_earns_a_reminder()
    {
        Assert.Equal(LowBalanceCall.None,
            LowBalanceAlerter.Evaluate(5000m, 4000m, Now - LowBalanceAlerter.RemindAfter + TimeSpan.FromMinutes(1), Now));
        Assert.Equal(LowBalanceCall.Remind,
            LowBalanceAlerter.Evaluate(5000m, 4000m, Now - LowBalanceAlerter.RemindAfter, Now));
    }

    [Fact]
    public void A_threshold_of_zero_means_alert_on_going_negative()
    {
        Assert.Equal(LowBalanceCall.None, LowBalanceAlerter.Evaluate(0m, 0m, null, Now));
        Assert.Equal(LowBalanceCall.Send, LowBalanceAlerter.Evaluate(0m, -0.01m, null, Now));
    }

    [Fact]
    public void Message_names_the_account_and_both_amounts()
    {
        var account = new Account
        {
            Name = "White card", Bank = "Monobank", Currency = "UAH",
            Balance = 4250.50m, LowBalanceThreshold = 5000m,
        };

        var first = LowBalanceAlerter.FormatMessage(account, reminder: false);
        Assert.Equal("⚠️ Monobank · White card is down to 4,250.5 UAH — below the 5,000 UAH limit. Time to top it up.", first);

        var reminder = LowBalanceAlerter.FormatMessage(account, reminder: true);
        Assert.Equal("⚠️ Monobank · White card is still low: 4,250.5 UAH (limit 5,000 UAH).", reminder);
    }

    [Fact]
    public void Message_for_a_bankless_manual_account_uses_the_bare_name()
    {
        var account = new Account { Name = "Cash", Bank = "", Currency = "PLN", Balance = 80m, LowBalanceThreshold = 100m };
        Assert.StartsWith("⚠️ Cash is down to 80 PLN", LowBalanceAlerter.FormatMessage(account, reminder: false));
    }
}
