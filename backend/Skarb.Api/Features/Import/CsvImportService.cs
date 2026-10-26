using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Common.Services;

namespace Skarb.Api.Features.Import;

/// <param name="Warnings">Things worth a look that didn't stop the import, e.g. a balance that disagrees with the statement.</param>
public record ImportResult(int Imported, int Skipped, List<string> Errors, List<string>? Warnings = null);

/// <summary>
/// Generic CSV statement import (fallback for banks without API access, e.g. ZEN).
/// Parses rows into IncomingTransactions and hands them to the shared ingestion
/// pipeline, so dedupe/categorization behave exactly like a bank sync.
/// </summary>
public class CsvImportService(SkarbDbContext db, ITransactionIngestor ingestor)
{
    public async Task<ImportResult> ImportAsync(Account account, CsvImportRequest req, CancellationToken ct)
    {
        if (string.Equals(req.Format, CsvFormats.Zen, StringComparison.OrdinalIgnoreCase))
            return await ImportZenAsync(account, req.Content, ct);

        var decimalSeparator = req.DecimalSeparator ?? ".";
        var delimiter = string.IsNullOrEmpty(req.Delimiter) ? ',' : req.Delimiter[0];

        var errors = new List<string>();
        var incoming = new List<IncomingTransaction>();
        var lines = CsvParser.Split(req.Content, delimiter);
        // Rows identical within one file are usually genuine repeats (two coffees the
        // same day) — number them so ids stay unique yet deterministic on re-import.
        var seenInFile = new Dictionary<string, int>();

        foreach (var (fields, index) in lines.Select((l, i) => (l, i)))
        {
            if (req.HasHeader && index == 0) continue;
            if (fields.Count == 0 || fields.All(string.IsNullOrWhiteSpace)) continue;

            try
            {
                var maxCol = Math.Max(req.DateColumn, Math.Max(req.AmountColumn, req.DescriptionColumn));
                if (fields.Count <= maxCol)
                {
                    errors.Add($"Row {index + 1}: expected at least {maxCol + 1} columns, got {fields.Count}");
                    continue;
                }

                var rawAmount = fields[req.AmountColumn].Trim().Replace(" ", "").Replace(" ", "");
                if (decimalSeparator == ",")
                    rawAmount = rawAmount.Replace(".", "").Replace(',', '.');
                var amount = decimal.Parse(rawAmount, CultureInfo.InvariantCulture);
                if (req.InvertAmount) amount = -amount;

                var rawDate = fields[req.DateColumn].Trim();
                var date = string.IsNullOrEmpty(req.DateFormat)
                    ? DateTime.Parse(rawDate, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal)
                    : DateTime.SpecifyKind(DateTime.ParseExact(rawDate, req.DateFormat, CultureInfo.InvariantCulture), DateTimeKind.Utc);

                var description = fields[req.DescriptionColumn].Trim().Trim('"');
                var currency = req.CurrencyColumn is int cc && fields.Count > cc && !string.IsNullOrWhiteSpace(fields[cc])
                    ? fields[cc].Trim().ToUpperInvariant()
                    : account.Currency;

                var externalId = RowId(date, amount, description, seenInFile);

                incoming.Add(new IncomingTransaction(externalId, amount, currency, description, date, TransactionSources.Import));
            }
            catch (Exception ex)
            {
                errors.Add($"Row {index + 1}: {ex.Message}");
            }
        }

        // The ingestor treats already-known external ids as updates, which for CSV means "skip".
        var imported = await ingestor.IngestAsync(account, incoming, ct);
        await ManualAccountBalance.RecomputeAsync(db, account, ct);

        return new ImportResult(imported, incoming.Count - imported, errors);
    }

    private async Task<ImportResult> ImportZenAsync(Account account, string content, CancellationToken ct)
    {
        var statement = ZenStatementParser.Parse(content);

        // ZEN exports one file per wallet, and the two look alike — a PLN statement imported into
        // the EUR account would land zloty amounts in a euro balance without anything looking off.
        if (statement.Currency is { } currency && currency != account.Currency)
            throw new InvalidOperationException(
                $"This is the {currency} statement, but \"{account.Name}\" is a {account.Currency} account. " +
                $"Pick the {currency} account, or export the {account.Currency} statement.");

        var errors = statement.Errors.ToList();
        var rows = new List<IncomingTransaction>();
        foreach (var row in statement.Rows)
        {
            if (row.Currency == account.Currency) rows.Add(row);
            else errors.Add($"{row.OccurredAtUtc:yyyy-MM-dd} {row.Description}: settled in {row.Currency}, not {account.Currency} — skipped.");
        }

        // The wallet's own IBAN is what a bank transfer into it names, so with it on the account a
        // PKO → ZEN transfer is recognised as internal by its counterparty alone.
        if (string.IsNullOrEmpty(account.Iban) && statement.Iban is { } iban &&
            !await db.Accounts.AnyAsync(a => a.Id != account.Id && a.Iban == iban, ct))
        {
            account.Iban = iban;
            await db.SaveChangesAsync(ct);
        }

        var imported = await ingestor.IngestAsync(account, rows, ct);
        await ManualAccountBalance.RecomputeAsync(db, account, ct);

        var warnings = new List<string>();
        if (await BalanceMismatchAsync(account, statement.ClosingBalance, rows, ct) is { } mismatch) warnings.Add(mismatch);
        return new ImportResult(imported, rows.Count - imported, errors, warnings);
    }

    /// <summary>
    /// A manual account's balance is the sum of its rows, so it only matches the bank once the
    /// opening balance is in there too. Checked only when this statement is the account's latest —
    /// an older one closing differently is expected.
    /// </summary>
    private async Task<string?> BalanceMismatchAsync(
        Account account, decimal? closing, List<IncomingTransaction> rows, CancellationToken ct)
    {
        if (account.Provider != ProviderNames.Manual || closing is not { } expected || rows.Count == 0) return null;
        var nextDay = rows.Max(r => r.OccurredAtUtc).Date.AddDays(1);
        // Excluded rows are skipped here because the opening balance is one, dated the day the account was made.
        if (await db.Transactions.AnyAsync(t => t.AccountId == account.Id && !t.IsExcluded && t.OccurredAt >= nextDay, ct))
            return null;
        if (account.Balance == expected) return null;

        var diff = expected - account.Balance;
        return $"ZEN says this wallet closed at {expected:0.00} {account.Currency}, Skarb shows {account.Balance:0.00}. " +
               $"The {diff:+0.00;-0.00} difference is usually the opening balance from before the statement's first day — " +
               "add it as an excluded transaction to line the two up.";
    }

    /// <summary>
    /// The external id of one imported row: the re-import dedupe contract. Shared by every CSV path
    /// so the same statement row gets the same id whichever way it was read.
    /// </summary>
    internal static string RowId(DateTime date, decimal amount, string description, Dictionary<string, int> seenInFile)
    {
        var baseHash = StableId.From("csv_", $"{date:yyyy-MM-dd}|{amount}|{description}");
        var occurrence = seenInFile[baseHash] = seenInFile.GetValueOrDefault(baseHash) + 1;
        return occurrence == 1 ? baseHash : $"{baseHash}_{occurrence}";
    }
}

public static class CsvFormats
{
    /// <summary>ZEN.com's own statement layout, read by <see cref="ZenStatementParser"/> instead of by column numbers.</summary>
    public const string Zen = "zen";
}

/// <summary>Minimal CSV parser with quoted-field support.</summary>
public static class CsvParser
{
    public static List<List<string>> Split(string content, char delimiter)
    {
        var rows = new List<List<string>>();
        var field = new System.Text.StringBuilder();
        var row = new List<string>();
        var inQuotes = false;

        for (var i = 0; i < content.Length; i++)
        {
            var c = content[i];
            if (inQuotes)
            {
                if (c == '"' && i + 1 < content.Length && content[i + 1] == '"') { field.Append('"'); i++; }
                else if (c == '"') inQuotes = false;
                else field.Append(c);
            }
            else if (c == '"') inQuotes = true;
            else if (c == delimiter) { row.Add(field.ToString()); field.Clear(); }
            else if (c is '\n' or '\r')
            {
                if (c == '\r' && i + 1 < content.Length && content[i + 1] == '\n') i++;
                row.Add(field.ToString());
                field.Clear();
                if (row.Count > 1 || !string.IsNullOrWhiteSpace(row[0])) rows.Add(row);
                row = [];
            }
            else field.Append(c);
        }
        if (field.Length > 0 || row.Count > 0)
        {
            row.Add(field.ToString());
            if (row.Count > 1 || !string.IsNullOrWhiteSpace(row[0])) rows.Add(row);
        }
        return rows;
    }
}
