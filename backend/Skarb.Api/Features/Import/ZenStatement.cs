using System.Globalization;
using System.Text.RegularExpressions;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;

namespace Skarb.Api.Features.Import;

/// <summary>A ZEN.com per-currency account statement, read by its own header rather than by column numbers.</summary>
/// <param name="Currency">The wallet's currency, from the statement's "Currency:" line.</param>
/// <param name="Iban">The wallet's local IBAN — not the "Global IBAN", which every wallet shares.</param>
public sealed record ZenStatement(
    string? Currency, string? Iban, decimal? ClosingBalance,
    List<IncomingTransaction> Rows, List<string> Errors);

/// <summary>
/// Reads the CSV statement the ZEN app generates (Wallet → currency → Statements). It is not a
/// plain table: a block of owner and account details comes first, then a "Transactions:" table
/// whose columns are found by name, then a legal footer. Reading it as such is what lets the
/// import keep the parts a fixed column mapping throws away — the transaction type and, on a
/// currency exchange, the other wallet's side of it, which is the only link between the two legs.
/// </summary>
public static partial class ZenStatementParser
{
    private static readonly string[] DateFormats = ["d MMM yyyy", "dd MMM yyyy"];

    /// <exception cref="InvalidOperationException">The file has no ZEN transaction table — the wrong file was picked.</exception>
    public static ZenStatement Parse(string content)
    {
        var rows = CsvParser.Split(content, ',');
        var errors = new List<string>();
        var incoming = new List<IncomingTransaction>();
        string? currency = null, iban = null;
        decimal? closing = null;

        var (headerIndex, col) = FindHeader(rows) ?? throw new InvalidOperationException(
            "This doesn't look like a ZEN statement: there is no \"Date, Transaction type, Description, " +
            "Settlement amount…\" table in it. Export it from the ZEN app as CSV, one file per currency.");

        foreach (var fields in rows.Take(headerIndex))
        {
            var first = fields[0].Trim();
            if (Field(first, "Currency:") is { } c) currency = c.ToUpperInvariant();
            else if (Field(first, "Local IBAN/Account Number:") is { } i) iban = LocalIban(i);
            else if (first.Equals("Closing balance:", StringComparison.OrdinalIgnoreCase) && fields.Count > 1 &&
                     decimal.TryParse(fields[1].Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out var cb))
                closing = cb;
        }

        // Rows that are identical within one file are usually genuine repeats — numbered the same
        // way the generic import numbers them, so either path yields the same ids for the same file.
        var seenInFile = new Dictionary<string, int>();
        var needed = new[] { col.Date, col.Type, col.Description, col.Amount, col.Currency }.Max();

        for (var index = headerIndex + 1; index < rows.Count; index++)
        {
            var fields = rows[index];
            // The footer ("This is a computer-generated document…") is one long field; so is any
            // blank line between the table and it. Neither is a transaction or an error.
            if (fields.Count <= needed) continue;

            try
            {
                var rawDate = fields[col.Date].Trim();
                if (!DateTime.TryParseExact(rawDate, DateFormats, CultureInfo.InvariantCulture,
                        DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var date))
                    date = DateTime.Parse(rawDate, CultureInfo.InvariantCulture,
                        DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal);

                var amount = decimal.Parse(fields[col.Amount].Trim(), NumberStyles.Number, CultureInfo.InvariantCulture);
                var rowCurrency = fields[col.Currency].Trim().ToUpperInvariant();
                var type = fields[col.Type].Trim();
                var rawDescription = fields[col.Description].Trim().Trim('"');

                var externalId = CsvImportService.RowId(date, amount, rawDescription, seenInFile);

                decimal? originalAmount = null;
                string? originalCurrency = null;
                if (col.OriginalAmount is int oa && col.OriginalCurrency is int oc && fields.Count > Math.Max(oa, oc))
                {
                    var origCur = fields[oc].Trim().ToUpperInvariant();
                    if (origCur.Length == 3 && origCur != rowCurrency &&
                        decimal.TryParse(fields[oa].Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out var origAmt))
                        (originalAmount, originalCurrency) = (origAmt, origCur);
                }

                var counterIban = IsTransfer(type) && Iban().Match(rawDescription) is { Success: true } m ? m.Value : null;

                incoming.Add(new IncomingTransaction(
                    externalId, amount, rowCurrency, Spaces().Replace(rawDescription, " "), date, TransactionSources.Import)
                {
                    TypeCode = type.Length > 0 ? type : null,
                    CounterIban = counterIban,
                    OriginalAmount = originalAmount,
                    OriginalCurrency = originalCurrency,
                });
            }
            catch (Exception ex) when (ex is FormatException or OverflowException)
            {
                errors.Add($"Row {index + 1}: {ex.Message}");
            }
        }

        return new ZenStatement(currency, iban, closing, incoming, errors);
    }

    private sealed record Columns(
        int Date, int Type, int Description, int Amount, int Currency, int? OriginalAmount, int? OriginalCurrency);

    private static (int Index, Columns Columns)? FindHeader(List<List<string>> rows)
    {
        for (var i = 0; i < rows.Count; i++)
        {
            var names = rows[i].Select(f => f.Trim().ToLowerInvariant()).ToList();
            int At(string name) => names.IndexOf(name);
            int? Optional(string name) => At(name) is var n and >= 0 ? n : null;

            var (date, amount) = (At("date"), At("settlement amount"));
            if (date < 0 || amount < 0) continue;
            var (type, description, currency) = (At("transaction type"), At("description"), At("settlement currency"));
            if (type < 0 || description < 0 || currency < 0) continue;
            return (i, new Columns(date, type, description, amount, currency,
                Optional("original amount"), Optional("original currency")));
        }
        return null;
    }

    /// <summary>
    /// The PLN wallet's "local IBAN" is printed as a bare 26-digit Polish account number. Banks
    /// name it with the country code when they report the transfer, so it gets one here — without
    /// it a PKO → ZEN transfer would never match the wallet by IBAN.
    /// </summary>
    internal static string LocalIban(string raw)
    {
        var iban = raw.Replace(" ", "").ToUpperInvariant();
        return iban.Length == 26 && iban.All(char.IsAsciiDigit) ? "PL" + iban : iban;
    }

    private static string? Field(string line, string label) =>
        line.StartsWith(label, StringComparison.OrdinalIgnoreCase) && line[label.Length..].Trim() is { Length: > 0 } v ? v : null;

    /// <summary>
    /// Only transfers name an account in their description. A card row's descriptor can hold a
    /// long alphanumeric merchant code that would read as an IBAN.
    /// </summary>
    private static bool IsTransfer(string type) => type.Contains("transfer", StringComparison.OrdinalIgnoreCase);

    [GeneratedRegex(@"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b")]
    private static partial Regex Iban();

    [GeneratedRegex(@"\s{2,}")]
    private static partial Regex Spaces();
}
