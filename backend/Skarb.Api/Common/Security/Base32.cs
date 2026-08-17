using System.Text;

namespace Skarb.Api.Common.Security;

/// <summary>
/// RFC 4648 Base32 without padding — the encoding every authenticator app expects for a
/// TOTP shared secret.
/// </summary>
internal static class Base32
{
    private const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    public static string Encode(ReadOnlySpan<byte> data)
    {
        var sb = new StringBuilder((data.Length * 8 + 4) / 5);
        int buffer = 0, bits = 0;
        foreach (var b in data)
        {
            buffer = (buffer << 8) | b;
            bits += 8;
            while (bits >= 5)
            {
                sb.Append(Alphabet[(buffer >> (bits - 5)) & 31]);
                bits -= 5;
            }
        }
        if (bits > 0) sb.Append(Alphabet[(buffer << (5 - bits)) & 31]);
        return sb.ToString();
    }

    /// <summary>Tolerates the spaces, dashes and lower case people paste in. Throws on real garbage.</summary>
    public static byte[] Decode(string encoded)
    {
        var bytes = new List<byte>(encoded.Length * 5 / 8);
        int buffer = 0, bits = 0;
        foreach (var c in encoded)
        {
            if (c is '=' or ' ' or '-' or '\t') continue;
            var index = Alphabet.IndexOf(char.ToUpperInvariant(c));
            if (index < 0) throw new FormatException($"'{c}' is not a Base32 character.");
            buffer = (buffer << 5) | index;
            bits += 5;
            if (bits < 8) continue;
            bytes.Add((byte)((buffer >> (bits - 8)) & 0xFF));
            bits -= 8;
        }
        return [.. bytes];
    }
}
