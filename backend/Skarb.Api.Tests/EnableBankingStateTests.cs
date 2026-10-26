using Skarb.Api.Features.Connections;

namespace Skarb.Api.Tests;

/// <summary>
/// The state is the only thing the web page can tell an app-started authorization by when Enable
/// Banking redirects it back to /settings, and the app reads the connection id back out of it —
/// so its shape is a contract between three clients.
/// </summary>
public class EnableBankingStateTests
{
    private static readonly Guid Connection = Guid.Parse("4b2f0d6e-90a1-4c3b-9d8e-1f2a3b4c5d6e");

    [Fact]
    public void A_web_authorization_keeps_the_bare_connection_id()
    {
        Assert.Equal(Connection.ToString(), EnableBankingState.For(Connection, null));
        Assert.Equal(Connection.ToString(), EnableBankingState.For(Connection, "web"));
    }

    [Fact]
    public void An_app_authorization_carries_the_connection_id_after_the_prefix()
    {
        Assert.Equal("app:" + Connection, EnableBankingState.For(Connection, "app"));
    }

    [Fact]
    public void The_client_name_is_read_forgivingly()
    {
        Assert.Equal("app:" + Connection, EnableBankingState.For(Connection, " App "));
    }
}
