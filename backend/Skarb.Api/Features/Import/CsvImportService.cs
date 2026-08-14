using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Import;

public record CsvMapping(
    int DateColumn,
    int AmountColumn,
    int DescriptionColumn,
    int? CurrencyColumn,
    string DateFormat,       // "" => flexible parse
    string DecimalSeparator, // "." or ","
    char Delimiter,
    bool HasHeader,
    bool InvertAmount);

public record ImportResult(int Imported, int Skipped, List<string> Errors);

/// <summary>
/// Generic CSV statement import (fallback for banks without API access, e.g. ZEN).
/// Parses rows into IncomingTransactions and hands them to the shared ingestion
/// pipeline, so dedupe/categorization behave exactly like a bank sync.
/// </summary>
public class CsvImportService(SkarbDbContext db, ITransactionIngestor ingestor)
{
    public async Task<ImportResult> ImportAsync(Account account, string csvContent, CsvMapping map, CancellationToken ct)
    {
        var errors = new List<string>();
        var incoming = new List<IncomingTransaction>();
        var lines = CsvParser.Split(csvContent, map.Delimiter);
        // Rows identical within one file are usually genuine repeats (two coffees the
        // same day) — number them so ids stay unique yet deterministic on re-import.
        var seenInFile = new Dictionary<string, int>();

        foreach (var (fields, index) in lines.Select((l, i) => (l, i)))
        {
            if (map.HasHeader && index == 0) continue;
            if (fields.Count == 0 || fields.All(string.IsNullOrWhiteSpace)) continue;

            try
            {
                var maxCol = Math.Max(map.DateColumn, Math.Max(map.AmountColumn, map.DescriptionColumn));
                if (fields.Count <= maxCol)
                {
                    errors.Add($"Row {index + 1}: expected at least {maxCol + 1} columns, got {fields.Count}");
                    continue;
                }

                var rawAmount = fields[map.AmountColumn].Trim().Replace(" ", "").Replace(" ", "");
                if (map.DecimalSeparator == ",")
                    rawAmount = rawAmount.Replace(".", "").Replace(',', '.');
                var amount = decimal.Parse(rawAmount, CultureInfo.InvariantCulture);
                if (map.InvertAmount) amount = -amount;

                var rawDate = fields[map.DateColumn].Trim();
                var date = string.IsNullOrEmpty(map.DateFormat)
                    ? DateTime.Parse(rawDate, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal)
                    : DateTime.SpecifyKind(DateTime.ParseExact(rawDate, map.DateFormat, CultureInfo.InvariantCulture), DateTimeKind.Utc);

                var description = fields[map.DescriptionColumn].Trim().Trim('"');
                var currency = map.CurrencyColumn is int cc && fields.Count > cc && !string.IsNullOrWhiteSpace(fields[cc])
                    ? fields[cc].Trim().ToUpperInvariant()
                    : account.Currency;

                var baseHash = "csv_" + Convert.ToHexString(
                    SHA256.HashData(Encoding.UTF8.GetBytes($"{date:yyyy-MM-dd}|{amount}|{description}")))[..24].ToLowerInvariant();
                var occurrence = seenInFile[baseHash] = seenInFile.GetValueOrDefault(baseHash) + 1;
                var externalId = occurrence == 1 ? baseHash : $"{baseHash}_{occurrence}";

                incoming.Add(new IncomingTransaction(externalId, amount, currency, description, date, TransactionSources.Import));
            }
            catch (Exception ex)
            {
                errors.Add($"Row {index + 1}: {ex.Message}");
            }
        }

        // The ingestor treats already-known external ids as updates, which for CSV means "skip".
        var imported = await ingestor.IngestAsync(account, incoming, ct);

        // Manual accounts keep a running balance from their transactions.
        if (account.Provider == ProviderNames.Manual)
        {
            account.Balance = await db.Transactions.Where(t => t.AccountId == account.Id).SumAsync(t => t.Amount, ct);
            await db.SaveChangesAsync(ct);
        }

        return new ImportResult(imported, incoming.Count - imported, errors);
    }
}

/// <summary>Minimal CSV parser with quoted-field support.</summary>
public static class CsvParser
{
    public static List<List<string>> Split(string content, char delimiter)
    {
        var rows = new List<List<string>>();
        var field = new StringBuilder();
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
