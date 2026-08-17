using Microsoft.Extensions.Options;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Security;

/// <summary>Where the instance stands: unclaimed, half-claimed, or ready to sign in to.</summary>
public sealed record SetupState(bool OwnerExists, bool Completed);

/// <summary>What the authenticator app needs in order to start producing codes.</summary>
public sealed record SetupChallenge(string Secret, string ProvisioningUri);

/// <summary>
/// First-run claiming of the instance, as a two-step handshake: create the credentials and
/// hand back a TOTP secret, then require a working code before the account becomes usable.
/// Enrolment cannot half-succeed and leave the owner locked out of their own deployment.
/// </summary>
public interface IOwnerSetup
{
    Task<SetupState> GetStateAsync(CancellationToken ct = default);
    Task<SetupChallenge> BeginAsync(string email, string password, CancellationToken ct = default);
    /// <summary>Returns the recovery codes on success, null when the code did not verify.</summary>
    Task<(OwnerAccount Owner, IReadOnlyList<string> RecoveryCodes)?> CompleteAsync(string code, CancellationToken ct = default);
}

public sealed class OwnerSetupService(
    IOwnerStore owners,
    IPasswordHasher passwords,
    ITotpAuthenticator totp,
    IRecoveryCodeService recovery,
    IOptions<AuthOptions> options) : IOwnerSetup
{
    public async Task<SetupState> GetStateAsync(CancellationToken ct = default)
    {
        var owner = await owners.GetAsync(ct);
        return new SetupState(owner is not null, owner?.TotpEnabled ?? false);
    }

    public async Task<SetupChallenge> BeginAsync(string email, string password, CancellationToken ct = default)
    {
        var normalizedEmail = email.Trim();
        var owner = new OwnerAccount
        {
            Email = normalizedEmail,
            PasswordHash = passwords.Hash(password),
            TotpSecret = totp.GenerateSecret(),
            TotpEnabled = false,
        };

        await owners.CreateAsync(owner, ct);

        return new SetupChallenge(
            owner.TotpSecret,
            totp.BuildProvisioningUri(owner.TotpSecret, normalizedEmail, options.Value.Issuer));
    }

    public async Task<(OwnerAccount, IReadOnlyList<string>)?> CompleteAsync(string code, CancellationToken ct = default)
    {
        var owner = await owners.GetAsync(ct);
        if (owner is null || owner.TotpEnabled) return null;

        var step = totp.Validate(owner.TotpSecret, code, owner.LastTotpStep);
        if (step is null) return null;

        owner.LastTotpStep = step.Value;
        owner.TotpEnabled = true;
        var codes = recovery.Issue(owner);
        await owners.SaveAsync(owner, ct);

        return (owner, codes);
    }
}
