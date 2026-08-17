using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace Skarb.Api.Common.Security;

/// <summary>Guards the one-time first-run claim of an unowned instance.</summary>
public interface ISetupTokenProvider
{
    string Token { get; }
    /// <summary>True when the caller presented the right token. Constant-time.</summary>
    bool Matches(string? candidate);
}

/// <summary>
/// A deployed-but-unclaimed instance is a land grab waiting to happen: whoever loads the
/// URL first would own the ledger. Setup therefore requires a token that only somebody with
/// access to the server's configuration or logs can see.
/// </summary>
public sealed class SetupTokenProvider : ISetupTokenProvider
{
    public string Token { get; }

    /// <summary>True when the token was generated here rather than configured, so it needs announcing.</summary>
    public bool IsGenerated { get; }

    public SetupTokenProvider(IOptions<AuthOptions> options)
    {
        var configured = options.Value.SetupToken;
        IsGenerated = string.IsNullOrWhiteSpace(configured);
        Token = IsGenerated ? Base32.Encode(RandomNumberGenerator.GetBytes(15)) : configured!.Trim();
    }

    public bool Matches(string? candidate) =>
        !string.IsNullOrWhiteSpace(candidate) &&
        CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(candidate.Trim()),
            Encoding.UTF8.GetBytes(Token));
}
