using System.Buffers.Binary;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Skarb.Api.Common.Security;

/// <summary>
/// RFC 6238 TOTP, the format every authenticator app speaks (1Password, Aegis, Google
/// Authenticator, Bitwarden). HMAC-SHA1 is not a free choice here — it is what the spec's
/// default profile mandates and what the apps interoperate on; the construction's security
/// does not rest on SHA-1 collision resistance.
/// </summary>
public sealed class TotpAuthenticator(TimeProvider clock) : ITotpAuthenticator
{
    private const int StepSeconds = 30;
    private const int Digits = 6;
    /// <summary>Accept one step either side, covering ~30 s of clock skew between phone and server.</summary>
    private const int DriftSteps = 1;
    private const int SecretBytes = 20;

    public string GenerateSecret() => Base32.Encode(RandomNumberGenerator.GetBytes(SecretBytes));

    public long? Validate(string secretBase32, string code, long mustExceedStep)
    {
        if (string.IsNullOrWhiteSpace(secretBase32)) return null;

        // Authenticator apps display "123 456"; accept whatever spacing the user typed.
        var digits = new string(code.Where(char.IsAsciiDigit).ToArray());
        if (digits.Length != Digits) return null;

        byte[] key;
        try
        {
            key = Base32.Decode(secretBase32);
        }
        catch (FormatException)
        {
            return null;
        }
        if (key.Length == 0) return null;

        var expected = Encoding.ASCII.GetBytes(digits);
        var current = clock.GetUtcNow().ToUnixTimeSeconds() / StepSeconds;

        for (var step = current - DriftSteps; step <= current + DriftSteps; step++)
        {
            // Refuse a code already spent: within the drift window the same six digits stay
            // valid for a while, and a shoulder-surfed code must not be replayable.
            if (step <= mustExceedStep) continue;
            if (CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(Compute(key, step)), expected))
                return step;
        }
        return null;
    }

    public string BuildProvisioningUri(string secretBase32, string accountName, string issuer)
    {
        var label = $"{Uri.EscapeDataString(issuer)}:{Uri.EscapeDataString(accountName)}";
        return $"otpauth://totp/{label}?secret={secretBase32}&issuer={Uri.EscapeDataString(issuer)}" +
               $"&algorithm=SHA1&digits={Digits}&period={StepSeconds}";
    }

    private static string Compute(byte[] key, long step)
    {
        Span<byte> counter = stackalloc byte[8];
        BinaryPrimitives.WriteInt64BigEndian(counter, step);

        Span<byte> mac = stackalloc byte[20];
        HMACSHA1.HashData(key, counter, mac);

        // Dynamic truncation (RFC 4226 §5.3): the low nibble of the last byte picks the offset.
        var offset = mac[^1] & 0x0F;
        var binary = ((mac[offset] & 0x7F) << 24)
                     | (mac[offset + 1] << 16)
                     | (mac[offset + 2] << 8)
                     | mac[offset + 3];
        return (binary % 1_000_000).ToString("D6", CultureInfo.InvariantCulture);
    }
}
