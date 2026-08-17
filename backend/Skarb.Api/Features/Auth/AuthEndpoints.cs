using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Security;

namespace Skarb.Api.Features.Auth;

public record SetupRequest(string SetupToken, string Email, string Password);
public record SetupConfirmRequest(string SetupToken, string Code);
public record LoginBody(string Email, string Password, string? Code, string? RecoveryCode);
public record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public record ConfirmPasswordRequest(string CurrentPassword);

/// <summary>
/// Sign-in surface. Everything here is deliberately thin: it translates HTTP to the
/// security policies in <c>Common/Security</c> and back, and holds no rules of its own.
/// </summary>
public class AuthEndpoints : IEndpointGroup
{
    /// <summary>Long enough to survive a leaked-password list; short enough that a passphrase works.</summary>
    private const int MinPasswordLength = 12;

    public void Map(IEndpointRouteBuilder app)
    {
        // Two things are deliberately per-endpoint rather than on the group:
        //  - AllowAnonymous, because it beats RequireAuthorization wherever both apply, so
        //    opening the group would silently unprotect the owner-only endpoints below;
        //  - rate limiting, which belongs on the handlers that verify a credential. /session is
        //    exempt: the SPA reads it on every load and throttling it would lock the UI out.
        var group = app.MapGroup("/api/auth");

        // ---------- public ----------

        group.MapGet("/session", async (HttpContext http, IOwnerSetup setup, CancellationToken ct) =>
        {
            var state = await setup.GetStateAsync(ct);
            var authenticated = http.User.Identity?.IsAuthenticated == true;
            return Results.Ok(new
            {
                authenticated,
                email = authenticated ? http.User.Identity!.Name : null,
                setupRequired = !state.Completed,
            });
        }).AllowAnonymous();

        group.MapPost("/setup", async (
            SetupRequest req, IOwnerSetup setup, ISetupTokenProvider tokens, CancellationToken ct) =>
        {
            if (!tokens.Matches(req.SetupToken))
                return Results.Json(new { error = "Invalid setup token." }, statusCode: StatusCodes.Status403Forbidden);

            var state = await setup.GetStateAsync(ct);
            if (state.Completed)
                return Results.Conflict(new { error = "This instance already has an owner." });

            if (string.IsNullOrWhiteSpace(req.Email) || !req.Email.Contains('@'))
                return Results.BadRequest(new { error = "Enter a valid email address." });
            if ((req.Password ?? "").Length < MinPasswordLength)
                return Results.BadRequest(new { error = $"Password must be at least {MinPasswordLength} characters." });

            var challenge = await setup.BeginAsync(req.Email, req.Password!, ct);
            return Results.Ok(new { secret = challenge.Secret, provisioningUri = challenge.ProvisioningUri });
        }).AllowAnonymous().RequireRateLimiting(RateLimitPolicies.Auth);

        group.MapPost("/setup/confirm", async (
            SetupConfirmRequest req, HttpContext http, IOwnerSetup setup, ISetupTokenProvider tokens,
            CancellationToken ct) =>
        {
            if (!tokens.Matches(req.SetupToken))
                return Results.Json(new { error = "Invalid setup token." }, statusCode: StatusCodes.Status403Forbidden);

            var completed = await setup.CompleteAsync(req.Code ?? "", ct);
            if (completed is null)
                return Results.BadRequest(new { error = "That code did not match. Check your authenticator and try again." });

            await http.SignInOwnerAsync(completed.Value.Owner);
            return Results.Ok(new { recoveryCodes = completed.Value.RecoveryCodes });
        }).AllowAnonymous().RequireRateLimiting(RateLimitPolicies.Auth);

        group.MapPost("/login", async (
            LoginBody body, HttpContext http, IOwnerAuthenticator authenticator, CancellationToken ct) =>
        {
            var result = await authenticator.AuthenticateAsync(
                new LoginRequest(body.Email ?? "", body.Password ?? "", body.Code, body.RecoveryCode), ct);

            switch (result.Status)
            {
                case LoginStatus.Success:
                    await http.SignInOwnerAsync(result.Owner!);
                    return Results.NoContent();

                case LoginStatus.LockedOut:
                    var minutes = Math.Max(1, (int)Math.Ceiling(result.RetryAfter!.Value.TotalMinutes));
                    return Results.Json(
                        new { error = $"Too many failed attempts. Try again in {minutes} minute{(minutes == 1 ? "" : "s")}." },
                        statusCode: StatusCodes.Status429TooManyRequests);

                case LoginStatus.SetupRequired:
                case LoginStatus.SetupIncomplete:
                    return Results.Conflict(new { error = "This instance still needs to be set up." });

                default:
                    return Results.Json(
                        new { error = "Invalid email, password or code." },
                        statusCode: StatusCodes.Status401Unauthorized);
            }
        }).AllowAnonymous().RequireRateLimiting(RateLimitPolicies.Auth);

        // ---------- owner only (deny-by-default fallback policy applies) ----------

        group.MapPost("/logout", async (HttpContext http) =>
        {
            await http.SignOutOwnerAsync();
            return Results.NoContent();
        });

        group.MapPost("/password", async (
            ChangePasswordRequest req, HttpContext http, IOwnerStore owners, IPasswordHasher passwords,
            CancellationToken ct) =>
        {
            var owner = await owners.GetAsync(ct);
            if (owner is null) return Results.Conflict(new { error = "No owner account." });

            if (passwords.Verify(owner.PasswordHash, req.CurrentPassword ?? "") is PasswordVerification.Failed)
                return AuthenticationExtensions.Unauthorized("Current password is incorrect.");
            if ((req.NewPassword ?? "").Length < MinPasswordLength)
                return Results.BadRequest(new { error = $"Password must be at least {MinPasswordLength} characters." });

            owner.PasswordHash = passwords.Hash(req.NewPassword!);
            owner.SecurityStamp = Guid.NewGuid().ToString("N"); // cuts every other live session
            await owners.SaveAsync(owner, ct);

            await http.SignInOwnerAsync(owner); // keep the browser that made the change signed in
            return Results.NoContent();
        }).RequireRateLimiting(RateLimitPolicies.Auth);

        group.MapPost("/recovery-codes", async (
            ConfirmPasswordRequest req, IOwnerStore owners, IPasswordHasher passwords,
            IRecoveryCodeService recovery, CancellationToken ct) =>
        {
            var owner = await owners.GetAsync(ct);
            if (owner is null) return Results.Conflict(new { error = "No owner account." });

            if (passwords.Verify(owner.PasswordHash, req.CurrentPassword ?? "") is PasswordVerification.Failed)
                return AuthenticationExtensions.Unauthorized("Current password is incorrect.");

            var codes = recovery.Issue(owner);
            await owners.SaveAsync(owner, ct);
            return Results.Ok(new { recoveryCodes = codes });
        }).RequireRateLimiting(RateLimitPolicies.Auth);

        group.MapGet("/recovery-codes/remaining", async (IOwnerStore owners, CancellationToken ct) =>
        {
            var owner = await owners.GetAsync(ct);
            return Results.Ok(new { remaining = owner?.RecoveryCodes.Count(r => r.UsedAt is null) ?? 0 });
        });
    }
}
