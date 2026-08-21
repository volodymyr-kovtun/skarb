using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace Skarb.Api.Common.Security;

/// <summary>
/// A local-only switch that signs every request in as the owner, with no password and no code.
/// It exists so the UI can be driven against a real database — layout work, screenshots, an agent
/// clicking through the app — without a second factor in the loop.
///
/// Two independent things have to be true before it does anything: the host must be in the
/// Development environment, and SKARB_DEV_AUTH_BYPASS must be set to "true". The flag is read from
/// the process environment rather than IConfiguration deliberately — appsettings.json is a
/// committed file, and a switch that removes authentication should never be one careless edit away
/// from riding along into a deployment. Asking for it anywhere else stops the app from starting.
/// </summary>
public static class DevAuthBypass
{
    public const string SchemeName = "DevAuthBypass";
    public const string Variable = "SKARB_DEV_AUTH_BYPASS";

    private static bool Requested =>
        string.Equals(Environment.GetEnvironmentVariable(Variable), "true", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Refuses to start rather than quietly ignoring the flag outside Development. A bypass that
    /// fails silently is one somebody eventually believes is off while it is on — or the reverse,
    /// and then works around the wrong problem.
    /// </summary>
    public static bool IsEnabled(IWebHostEnvironment environment)
    {
        if (!Requested) return false;
        if (environment.IsDevelopment()) return true;

        throw new InvalidOperationException(
            $"{Variable} is set, but the host is running as '{environment.EnvironmentName}', not Development. " +
            "This switch removes authentication from every endpoint and is refused outside local development. " +
            "Unset it and restart.");
    }
}

/// <summary>Hands every request the same synthetic identity. See <see cref="DevAuthBypass"/>.</summary>
public sealed class DevAuthBypassHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        // Deliberately not a real OwnerAccount, and deliberately not that owner's id: nothing
        // here should be mistakable, in a log or a session list, for someone who actually
        // proved they were entitled to be here.
        var identity = new ClaimsIdentity(
            [
                new Claim(ClaimTypes.NameIdentifier, Guid.Empty.ToString()),
                new Claim(ClaimTypes.Name, "dev-bypass@localhost"),
            ],
            DevAuthBypass.SchemeName);

        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identity), DevAuthBypass.SchemeName)));
    }
}
