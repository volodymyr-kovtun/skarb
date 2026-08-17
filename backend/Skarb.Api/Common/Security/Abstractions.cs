using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Security;

// ---------------------------------------------------------------- password hashing

public enum PasswordVerification
{
    Failed,
    Success,
    /// <summary>Correct password, but stored with outdated parameters — rehash it on the way through.</summary>
    SuccessNeedsRehash,
}

/// <summary>
/// Turns a password into an opaque, self-describing hash and back into a verdict.
/// Abstracted so the KDF can be upgraded without touching the sign-in policy (DIP).
/// </summary>
public interface IPasswordHasher
{
    string Hash(string password);
    PasswordVerification Verify(string hash, string password);
}

// ---------------------------------------------------------------- second factor

/// <summary>
/// RFC 6238 time-based one-time passwords. A second factor is a self-contained policy,
/// kept separate from password checking so either can change alone (SRP/ISP).
/// </summary>
public interface ITotpAuthenticator
{
    /// <summary>A fresh Base32 shared secret for an authenticator app.</summary>
    string GenerateSecret();

    /// <summary>
    /// Validates <paramref name="code"/> against the secret, accepting a small clock drift.
    /// Returns the accepted time step (always greater than <paramref name="mustExceedStep"/>)
    /// so the caller can persist it and refuse a replay of the same code; null when invalid.
    /// </summary>
    long? Validate(string secretBase32, string code, long mustExceedStep);

    /// <summary>The <c>otpauth://</c> URI an authenticator app scans or imports.</summary>
    string BuildProvisioningUri(string secretBase32, string accountName, string issuer);
}

/// <summary>Single-use codes that get the owner back in when the authenticator is lost.</summary>
public interface IRecoveryCodeService
{
    /// <summary>Replaces the owner's codes and returns the plaintext set — shown exactly once.</summary>
    IReadOnlyList<string> Issue(OwnerAccount owner, int count = 8);

    /// <summary>Marks a matching unused code as spent. False when nothing matches.</summary>
    bool Redeem(OwnerAccount owner, string code);
}

// ---------------------------------------------------------------- persistence

/// <summary>
/// The owner row, behind an interface so the sign-in policy never touches EF Core
/// and can be unit-tested against an in-memory stand-in (DIP).
/// </summary>
public interface IOwnerStore
{
    Task<OwnerAccount?> GetAsync(CancellationToken ct = default);
    Task<bool> ExistsAsync(CancellationToken ct = default);
    /// <summary>Persists pending changes to an owner already tracked or newly added.</summary>
    Task SaveAsync(OwnerAccount owner, CancellationToken ct = default);
    /// <summary>Creates the owner, discarding an earlier unfinished setup attempt.</summary>
    Task<OwnerAccount> CreateAsync(OwnerAccount owner, CancellationToken ct = default);
}

// ---------------------------------------------------------------- sign-in policy

public enum LoginStatus
{
    Success,
    /// <summary>Email, password, second factor or recovery code did not check out — deliberately undifferentiated.</summary>
    Rejected,
    /// <summary>Too many failed attempts; <see cref="LoginResult.RetryAfter"/> says how long to wait.</summary>
    LockedOut,
    /// <summary>No owner exists yet — the instance still has to be claimed.</summary>
    SetupRequired,
    /// <summary>Owner exists but never confirmed their authenticator, so no one can sign in yet.</summary>
    SetupIncomplete,
}

public sealed record LoginRequest(string Email, string Password, string? TotpCode, string? RecoveryCode);

public sealed record LoginResult(LoginStatus Status, OwnerAccount? Owner = null, TimeSpan? RetryAfter = null)
{
    public static readonly LoginResult Rejected = new(LoginStatus.Rejected);
}

/// <summary>
/// Decides whether a sign-in attempt succeeds. Owns password checking, the second factor
/// and lockout as one cohesive policy; issuing the cookie stays with the HTTP layer.
/// </summary>
public interface IOwnerAuthenticator
{
    Task<LoginResult> AuthenticateAsync(LoginRequest request, CancellationToken ct = default);
}

// ---------------------------------------------------------------- options

public sealed class AuthOptions
{
    public const string Section = "Auth";

    /// <summary>
    /// Gate for the one-time first-run claim. Left unset, Skarb generates one at startup and
    /// logs it, so an unclaimed public instance can't be taken over by whoever finds it first.
    /// </summary>
    public string? SetupToken { get; set; }

    /// <summary>How long a session cookie stays valid; refreshed on activity.</summary>
    public int SessionDays { get; set; } = 14;

    public int MaxFailedAttempts { get; set; } = 5;
    public int LockoutMinutes { get; set; } = 15;

    /// <summary>Label shown in the authenticator app next to the code.</summary>
    public string Issuer { get; set; } = "Skarb";

    /// <summary>
    /// Where data-protection keys live. These encrypt the session cookie, so a container
    /// without a persistent path here signs everyone out on every restart.
    /// </summary>
    public string? KeyRingPath { get; set; }

    /// <summary>Extra browser origins allowed to call the API with credentials (Vite dev server).</summary>
    public string[] AllowedOrigins { get; set; } = [];
}
