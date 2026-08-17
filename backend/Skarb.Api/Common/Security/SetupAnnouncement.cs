namespace Skarb.Api.Common.Security;

/// <summary>
/// Prints the first-run instructions when the instance has no usable owner yet. This is the
/// only channel the setup token travels on: whoever can read the server's log is, by
/// definition, already the person entitled to claim the deployment.
/// </summary>
public static class SetupAnnouncement
{
    public static async Task WriteIfUnclaimedAsync(IServiceProvider services, ILogger logger)
    {
        var state = await services.GetRequiredService<IOwnerSetup>().GetStateAsync();
        if (state.Completed) return;

        var tokens = services.GetRequiredService<ISetupTokenProvider>();

        if (tokens is SetupTokenProvider { IsGenerated: false })
        {
            logger.LogWarning(
                "Skarb has no owner yet. Open the app and complete setup using the configured Auth:SetupToken.");
            return;
        }

        logger.LogWarning(
            """

            ┌───────────────────────────────────────────────────────────────┐
            │  Skarb has no owner yet — open the app to claim it.           │
            │                                                               │
            │  Setup token:  {Token}
            │                                                               │
            │  This token is required once, to stop anyone else claiming    │
            │  the instance. Set Auth__SetupToken to choose your own.       │
            └───────────────────────────────────────────────────────────────┘

            """,
            tokens.Token);
    }
}
