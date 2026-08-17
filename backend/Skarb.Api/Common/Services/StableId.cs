using System.Security.Cryptography;
using System.Text;

namespace Skarb.Api.Common.Services;

/// <summary>
/// Deterministic external ids for sources that don't provide one (CSV rows,
/// Enable Banking items without entry_reference). The format is part of the
/// dedupe contract — changing it breaks re-import idempotency.
/// </summary>
public static class StableId
{
    public static string From(string prefix, string input) =>
        prefix + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input)))[..24].ToLowerInvariant();
}
