using Skarb.Api.Features.Sync;

namespace Skarb.Api.Tests;

/// <summary>
/// The auto-sync interval is the one config value that reaches Task.Delay on a background
/// service, and BackgroundServiceExceptionBehavior defaults to StopHost: before it was clamped,
/// Sync__IntervalMinutes=100000 threw past Task.Delay's ~49-day ceiling and killed the whole
/// API seconds after startup.
/// </summary>
public class SyncIntervalTests
{
    [Fact]
    public void A_sane_interval_is_used_as_configured()
    {
        Assert.Equal(TimeSpan.FromMinutes(30), BackgroundSyncService.ResolveInterval(30));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void Zero_or_less_still_means_auto_sync_is_off(int minutes)
    {
        Assert.Equal(TimeSpan.Zero, BackgroundSyncService.ResolveInterval(minutes));
    }

    [Fact]
    public void An_oversized_interval_is_clamped_instead_of_trusted()
    {
        Assert.Equal(
            TimeSpan.FromMinutes(BackgroundSyncService.MaxIntervalMinutes),
            BackgroundSyncService.ResolveInterval(100_000));
    }

    [Fact]
    public async Task Task_Delay_accepts_the_clamped_interval_for_any_configured_value()
    {
        using var cancelled = new CancellationTokenSource();
        await cancelled.CancelAsync();

        foreach (var minutes in new[] { 1, 30, 100_000, int.MaxValue })
        {
            var delay = BackgroundSyncService.ResolveInterval(minutes);

            // Task.Delay validates the range before it looks at the token, so reaching the
            // cancellation is the proof that the delay itself was acceptable.
            await Assert.ThrowsAsync<TaskCanceledException>(() => Task.Delay(delay, cancelled.Token));
        }
    }
}
