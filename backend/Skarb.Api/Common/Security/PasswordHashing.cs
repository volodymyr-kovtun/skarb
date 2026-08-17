using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;

namespace Skarb.Api.Common.Security;

/// <summary>
/// Adapter over ASP.NET Core Identity's vetted PBKDF2 hasher (HMAC-SHA512, 128-bit salt,
/// 256-bit subkey, version byte in the payload). Confining the dependency to this one class
/// keeps the rest of the app on <see cref="IPasswordHasher"/>, so the KDF can be swapped
/// for Argon2 later without a single call site changing.
/// </summary>
public sealed class Pbkdf2PasswordHasher : IPasswordHasher
{
    // OWASP's 2026 floor for PBKDF2-HMAC-SHA512. Raising it is safe: existing hashes carry
    // their own iteration count and get re-hashed on the next successful sign-in.
    private const int Iterations = 210_000;

    private static readonly object Subject = new();

    private readonly PasswordHasher<object> _inner = new(Options.Create(new PasswordHasherOptions
    {
        CompatibilityMode = PasswordHasherCompatibilityMode.IdentityV3,
        IterationCount = Iterations,
    }));

    public string Hash(string password) => _inner.HashPassword(Subject, password);

    public PasswordVerification Verify(string hash, string password)
    {
        if (string.IsNullOrEmpty(hash)) return PasswordVerification.Failed;
        try
        {
            return _inner.VerifyHashedPassword(Subject, hash, password) switch
            {
                PasswordVerificationResult.Success => PasswordVerification.Success,
                PasswordVerificationResult.SuccessRehashNeeded => PasswordVerification.SuccessNeedsRehash,
                _ => PasswordVerification.Failed,
            };
        }
        catch (FormatException)
        {
            return PasswordVerification.Failed; // corrupted/truncated hash column
        }
    }
}
