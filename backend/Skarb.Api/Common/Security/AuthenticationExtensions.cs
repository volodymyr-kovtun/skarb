using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.RateLimiting;
using Skarb.Api.Common.Domain;
using System.Threading.RateLimiting;

namespace Skarb.Api.Common.Security;

public static class RateLimitPolicies
{
    /// <summary>
    /// Applied to /api/auth. Password verification is deliberately expensive, which makes an
    /// unauthenticated flood a CPU exhaustion vector — this caps it per client address,
    /// independently of the per-account lockout.
    /// </summary>
    public const string Auth = "auth";

    public static IServiceCollection AddSkarbRateLimiting(this IServiceCollection services) =>
        services.AddRateLimiter(limiter =>
        {
            limiter.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            limiter.AddPolicy(Auth, http => RateLimitPartition.GetFixedWindowLimiter(
                http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions
                {
                    Window = TimeSpan.FromMinutes(1),
                    PermitLimit = 20,
                    QueueLimit = 0,
                }));
        });
}

public static class AuthenticationExtensions
{
    public const string CookieName = "skarb.session";
    private const string SecurityStampClaim = "skarb:stamp";

    /// <summary>
    /// Registers the sign-in policy, the session cookie and a deny-by-default authorization
    /// rule. The default matters most: every endpoint added from here on is protected unless
    /// it says otherwise, so a new feature slice cannot accidentally ship unauthenticated.
    /// </summary>
    public static IServiceCollection AddSkarbAuthentication(
        this IServiceCollection services, IConfiguration configuration, IWebHostEnvironment environment)
    {
        services.Configure<AuthOptions>(configuration.GetSection(AuthOptions.Section));
        services.TryAddSingletonTimeProvider();

        services.AddSingleton<IPasswordHasher, Pbkdf2PasswordHasher>();
        services.AddSingleton<ITotpAuthenticator, TotpAuthenticator>();
        services.AddSingleton<IRecoveryCodeService, RecoveryCodeService>();
        services.AddSingleton<ISetupTokenProvider, SetupTokenProvider>();
        services.AddScoped<IOwnerStore, OwnerStore>();
        services.AddScoped<IOwnerAuthenticator, OwnerAuthenticator>();
        services.AddScoped<IOwnerSetup, OwnerSetupService>();

        var auth = configuration.GetSection(AuthOptions.Section).Get<AuthOptions>() ?? new AuthOptions();

        // The session cookie is encrypted with data-protection keys. Left on the default
        // (a per-container directory), every restart would invalidate every session — so the
        // key ring goes somewhere the deployment can mount as a volume.
        services.AddDataProtection()
            .SetApplicationName("Skarb")
            .PersistKeysToFileSystem(new DirectoryInfo(
                auth.KeyRingPath is { Length: > 0 } path
                    ? path
                    : Path.Combine(environment.ContentRootPath, "keys")));

        // Local development may hand the default scheme to a bypass that authenticates everyone.
        // The cookie scheme stays registered either way, and sign-in/sign-out name it explicitly,
        // so the real login flow still works while the bypass is on.
        var bypass = DevAuthBypass.IsEnabled(environment);

        var schemes = services
            .AddAuthentication(bypass ? DevAuthBypass.SchemeName : CookieAuthenticationDefaults.AuthenticationScheme)
            .AddCookie(options =>
            {
                options.Cookie.Name = CookieName;
                options.Cookie.HttpOnly = true;
                options.Cookie.IsEssential = true;

                // Lax, not Strict: finishing a bank authorization is a top-level GET redirect
                // back from the bank's domain, and Strict would drop the cookie on arrival —
                // logging the user out exactly when Enable Banking hands the code back.
                options.Cookie.SameSite = SameSiteMode.Lax;
                options.Cookie.SecurePolicy = environment.IsDevelopment()
                    ? CookieSecurePolicy.SameAsRequest
                    : CookieSecurePolicy.Always;

                options.ExpireTimeSpan = TimeSpan.FromDays(Math.Max(1, auth.SessionDays));
                options.SlidingExpiration = true;

                // This is an API behind an SPA: answer with status codes, never a redirect to
                // a server-rendered login page that does not exist.
                options.Events.OnRedirectToLogin = ctx =>
                {
                    ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    return Task.CompletedTask;
                };
                options.Events.OnRedirectToAccessDenied = ctx =>
                {
                    ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
                    return Task.CompletedTask;
                };
                options.Events.OnValidatePrincipal = ValidateSecurityStampAsync;
            });

        if (bypass)
            schemes.AddScheme<AuthenticationSchemeOptions, DevAuthBypassHandler>(DevAuthBypass.SchemeName, null);

        services.AddAuthorizationBuilder()
            .SetFallbackPolicy(new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());

        return services;
    }

    /// <summary>
    /// Rejects cookies minted before the last credential change, which is what makes
    /// "change my password" actually end sessions on devices you no longer hold.
    /// </summary>
    private static async Task ValidateSecurityStampAsync(CookieValidatePrincipalContext context)
    {
        var stamp = context.Principal?.FindFirstValue(SecurityStampClaim);
        var owner = await context.HttpContext.RequestServices
            .GetRequiredService<IOwnerStore>()
            .GetAsync(context.HttpContext.RequestAborted);

        if (owner is not null && owner.TotpEnabled && stamp == owner.SecurityStamp) return;

        context.RejectPrincipal();
        await context.HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
    }

    /// <summary>The claims that make up a signed-in owner's session.</summary>
    public static ClaimsPrincipal ToPrincipal(this OwnerAccount owner)
    {
        var identity = new ClaimsIdentity(
            [
                new Claim(ClaimTypes.NameIdentifier, owner.Id.ToString()),
                new Claim(ClaimTypes.Name, owner.Email),
                new Claim(SecurityStampClaim, owner.SecurityStamp),
            ],
            CookieAuthenticationDefaults.AuthenticationScheme);

        return new ClaimsPrincipal(identity);
    }

    /// <summary>Starts a session for the owner on the current request.</summary>
    public static Task SignInOwnerAsync(this HttpContext http, OwnerAccount owner) =>
        http.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, owner.ToPrincipal(),
            new AuthenticationProperties { IsPersistent = true });

    public static Task SignOutOwnerAsync(this HttpContext http) =>
        http.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);

    /// <summary>Uniform 401 body so the SPA can tell "signed out" from a real failure.</summary>
    public static IResult Unauthorized(string message) =>
        Results.Json(new { error = message }, statusCode: StatusCodes.Status401Unauthorized);

    private static void TryAddSingletonTimeProvider(this IServiceCollection services)
    {
        if (services.All(d => d.ServiceType != typeof(TimeProvider)))
            services.AddSingleton(TimeProvider.System);
    }
}
