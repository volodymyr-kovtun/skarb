using Microsoft.Extensions.Options;

namespace Skarb.Api.Common.Security;

/// <summary>
/// The sign-in decision, in one place: identity, password, second factor and lockout.
/// It composes the small policies behind their interfaces and never touches HTTP or EF,
/// which is what makes the rule set readable and testable on its own.
/// </summary>
public sealed class OwnerAuthenticator(
    IOwnerStore owners,
    IPasswordHasher passwords,
    ITotpAuthenticator totp,
    IRecoveryCodeService recovery,
    IOptions<AuthOptions> options,
    TimeProvider clock,
    ILogger<OwnerAuthenticator> logger) : IOwnerAuthenticator
{
    public async Task<LoginResult> AuthenticateAsync(LoginRequest request, CancellationToken ct = default)
    {
        var owner = await owners.GetAsync(ct);
        if (owner is null) return new LoginResult(LoginStatus.SetupRequired);
        if (!owner.TotpEnabled) return new LoginResult(LoginStatus.SetupIncomplete);

        var now = clock.GetUtcNow().UtcDateTime;
        if (owner.LockedUntil is { } until && until > now)
            return new LoginResult(LoginStatus.LockedOut, RetryAfter: until - now);

        var identityOk = string.Equals(owner.Email, request.Email.Trim(), StringComparison.OrdinalIgnoreCase);
        var passwordCheck = passwords.Verify(owner.PasswordHash, request.Password);
        var credentialsOk = identityOk && passwordCheck is not PasswordVerification.Failed;

        // The second factor is only evaluated once the password holds up. Redeeming a recovery
        // code is destructive, so an unauthenticated request must never be able to burn one.
        long? acceptedStep = null;
        var secondFactorOk = false;
        if (credentialsOk)
        {
            if (!string.IsNullOrWhiteSpace(request.RecoveryCode))
            {
                secondFactorOk = recovery.Redeem(owner, request.RecoveryCode);
                if (secondFactorOk)
                    logger.LogWarning("Sign-in used a recovery code; {Remaining} remain",
                        owner.RecoveryCodes.Count(r => r.UsedAt is null));
            }
            else
            {
                acceptedStep = totp.Validate(owner.TotpSecret, request.TotpCode ?? "", owner.LastTotpStep);
                secondFactorOk = acceptedStep is not null;
            }
        }

        if (!credentialsOk || !secondFactorOk)
            return await RejectAsync(owner, now, ct);

        if (acceptedStep is { } step) owner.LastTotpStep = step;
        if (passwordCheck is PasswordVerification.SuccessNeedsRehash)
            owner.PasswordHash = passwords.Hash(request.Password);

        owner.FailedAttempts = 0;
        owner.LockedUntil = null;
        owner.LastLoginAt = now;
        await owners.SaveAsync(owner, ct);

        return new LoginResult(LoginStatus.Success, owner);
    }

    private async Task<LoginResult> RejectAsync(Domain.OwnerAccount owner, DateTime now, CancellationToken ct)
    {
        owner.FailedAttempts++;

        TimeSpan? retryAfter = null;
        if (owner.FailedAttempts >= options.Value.MaxFailedAttempts)
        {
            var lockout = TimeSpan.FromMinutes(options.Value.LockoutMinutes);
            owner.LockedUntil = now.Add(lockout);
            owner.FailedAttempts = 0;
            retryAfter = lockout;
            logger.LogWarning("Sign-in locked out until {Until:u} after {Max} failed attempts",
                owner.LockedUntil, options.Value.MaxFailedAttempts);
        }

        await owners.SaveAsync(owner, ct);
        return retryAfter is null ? LoginResult.Rejected : new LoginResult(LoginStatus.LockedOut, RetryAfter: retryAfter);
    }
}
