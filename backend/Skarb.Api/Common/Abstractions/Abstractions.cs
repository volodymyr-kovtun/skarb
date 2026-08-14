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
    Task<SyncResult> SyncAsync(BankConnection connection, CancellationToken ct);
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

/// <summary>Assigns a category to an incoming transaction.</summary>
public interface ICategorizer
{
    Task<Guid?> ResolveAsync(string description, string? counterParty, int? mcc, decimal amount, CancellationToken ct);
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

/// <summary>Converts amounts into the app's base currency.</summary>
public interface IExchangeRateService
{
    string BaseCurrency { get; }
    Task<decimal> ToBaseAsync(decimal amount, string currency, CancellationToken ct = default);
}

/// <summary>Triggers and tracks background syncs across bank connections.</summary>
public interface ISyncService
{
    IReadOnlyDictionary<Guid, string> Running { get; }
    Task<List<Guid>> TriggerAsync(Guid? connectionId = null);
}

public sealed class SyncOptions
{
    public const string Section = "Sync";
    public int IntervalMinutes { get; set; } = 30;
    public int InitialHistoryDays { get; set; } = 31;
    /// <summary>How far back the transfer detector looks for matching legs.</summary>
    public int TransferLookbackDays { get; set; } = 14;
}
