using System.Security.Cryptography;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Security;

/// <summary>
/// Single-use recovery codes. Without these, a lost or wiped phone means permanent
/// lock-out of your own ledger — the failure mode that makes people skip 2FA entirely.
/// </summary>
public sealed class RecoveryCodeService(IPasswordHasher hasher) : IRecoveryCodeService
{
    // No 0/o/1/l/i — these get read off a screen and typed back under stress.
    private const string Alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
    private const int HalfLength = 5;

    public IReadOnlyList<string> Issue(OwnerAccount owner, int count = 8)
    {
        var codes = Enumerable.Range(0, count).Select(_ => NewCode()).ToList();

        owner.RecoveryCodes.Clear();
        foreach (var code in codes)
            owner.RecoveryCodes.Add(new RecoveryCode
            {
                OwnerId = owner.Id,
                CodeHash = hasher.Hash(Normalize(code)),
            });

        return codes;
    }

    public bool Redeem(OwnerAccount owner, string code)
    {
        var normalized = Normalize(code);
        if (normalized.Length == 0) return false;

        foreach (var stored in owner.RecoveryCodes.Where(r => r.UsedAt is null))
        {
            if (hasher.Verify(stored.CodeHash, normalized) is PasswordVerification.Failed) continue;
            stored.UsedAt = DateTime.UtcNow;
            return true;
        }
        return false;
    }

    private static string NewCode() =>
        string.Concat(RandomNumberGenerator.GetString(Alphabet, HalfLength), "-",
                      RandomNumberGenerator.GetString(Alphabet, HalfLength));

    /// <summary>Codes are compared case- and separator-insensitively, however they were transcribed.</summary>
    private static string Normalize(string code) =>
        new([.. code.Where(char.IsAsciiLetterOrDigit).Select(char.ToLowerInvariant)]);
}
