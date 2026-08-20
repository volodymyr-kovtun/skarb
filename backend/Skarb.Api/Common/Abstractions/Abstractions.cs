using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Abstractions;

/// <summary>A feature's endpoint group. Implementations are discovered and mapped at startup.</summary>
public interface IEndpointGroup
{
    void Map(IEndpointRouteBuilder app);
}

/// <summary>
/// A bank integration capable of syncing accounts and transactions for a connection.
/// New providers plug in by implementing this and registering in DI — nothing else changes (OCP).
/// </summary>
public interface IBankProvider
{
    /// <summary>Matches <see cref="BankConnection.Provider"/>.</summary>
    string Key { get; }
    /// <param name="full">Ignore the incremental watermark and re-fetch the whole history window
    /// (re-maps existing rows through the ingestor — used after mapping/categorization improvements).</param>
    Task<SyncResult> SyncAsync(BankConnection connection, bool full, CancellationToken ct);
}

public sealed record SyncResult(int NewTransactions);

/// <summary>A transaction as reported by a bank/provider/import, before it enters the ledger.</summary>
public sealed record IncomingTransaction(
    string ExternalId,
    decimal Amount,
    string Currency,
    string Description,
    DateTime OccurredAtUtc,
    string Source)
{
    public string? CounterParty { get; init; }
    public string? CounterIban { get; init; }
    public int? Mcc { get; init; }
    /// <summary>Bank-supplied transaction type (e.g. "CARD-ATM", "FEE"), when available. Rules can match on it.</summary>
    public string? TypeCode { get; init; }
    public string? Note { get; init; }
}

/// <summary>
/// Single entry point for transactions flowing into the ledger (sync, webhook, CSV import):
/// deduplicates by external id, refreshes mutable fields of known items (bank holds),
/// and auto-categorizes new ones.
/// </summary>
public interface ITransactionIngestor
{
    /// <summary>Returns the number of newly created transactions.</summary>
    Task<int> IngestAsync(Account account, IReadOnlyCollection<IncomingTransaction> items, CancellationToken ct);
}

/// <summary>A category the categorizer picked, and which signal picked it.</summary>
/// <param name="Source">One of <see cref="Skarb.Api.Common.Domain.CategorySources"/>.</param>
public sealed record CategoryVerdict(Guid CategoryId, string Source);

/// <summary>Assigns a category to an incoming transaction.</summary>
public interface ICategorizer
{
    /// <summary>Null when nothing recognised the transaction — it stays uncategorized.</summary>
    Task<CategoryVerdict?> ResolveAsync(IncomingTransaction item, CancellationToken ct);
}

/// <summary>
/// Finds transfers between the user's own accounts and marks both legs as internal,
/// so moving money around never shows up as income or spending.
/// </summary>
public interface ITransferDetector
{
    /// <summary>Returns the number of transactions newly marked as internal.</summary>
    Task<int> DetectAsync(CancellationToken ct);
}

/// <summary>Converts amounts between currencies.</summary>
public interface IExchangeRateService
{
    /// <summary>Currency the app falls back to when none is requested.</summary>
    string BaseCurrency { get; }

    /// <summary>Converts between any two currencies with known rates; returns the amount unchanged otherwise.</summary>
    Task<decimal> ConvertAsync(decimal amount, string from, string to, CancellationToken ct = default);

    /// <summary>True when the currency has a known rate, i.e. amounts in it can be converted.</summary>
    Task<bool> IsKnownAsync(string currency, CancellationToken ct = default);
}

/// <summary>Triggers and tracks background syncs across bank connections.</summary>
public interface ISyncService
{
    IReadOnlyDictionary<Guid, string> Running { get; }
    Task<List<Guid>> TriggerAsync(Guid? connectionId = null, bool full = false);
}

public sealed class SyncOptions
{
    public const string Section = "Sync";
    public int IntervalMinutes { get; set; } = 30;
    public int InitialHistoryDays { get; set; } = 31;
    /// <summary>How far back the transfer detector looks for matching legs.</summary>
    public int TransferLookbackDays { get; set; } = 14;
    /// <summary>Maximum time between the two legs of a detected internal transfer.</summary>
    public int TransferPairWindowHours { get; set; } = 72;
}

public sealed class FxOptions
{
    public const string Section = "Fx";
    /// <summary>Currency the dashboard reports in. Fallback rates assume PLN.</summary>
    public string BaseCurrency { get; set; } = "PLN";
    public int CacheHours { get; set; } = 12;
}
