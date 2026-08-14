namespace Skarb.Api.Common.Domain;

public static class ProviderNames
{
    public const string Manual = "manual";
    public const string Monobank = "monobank";
    public const string EnableBanking = "enablebanking";
}

public static class CategoryKinds
{
    public const string Expense = "expense";
    public const string Income = "income";
    public const string Investment = "investment";
}

public static class TransactionSources
{
    public const string Manual = "manual";
    public const string Sync = "sync";
    public const string Webhook = "webhook";
    public const string Import = "import";
}

public class Account
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    /// <summary>Display name of the bank, e.g. "PKO BP", "ZEN", "Monobank".</summary>
    public string Bank { get; set; } = "";
    public string Provider { get; set; } = ProviderNames.Manual;
    public Guid? ConnectionId { get; set; }
    public BankConnection? Connection { get; set; }
    /// <summary>Provider-side account id (Monobank account id / Enable Banking account uid).</summary>
    public string? ExternalId { get; set; }
    public string Currency { get; set; } = "PLN";
    public decimal Balance { get; set; }
    /// <summary>Credit limit included in the provider-reported balance (Monobank).</summary>
    public decimal CreditLimit { get; set; }
    public string? Iban { get; set; }
    public string? MaskedPan { get; set; }
    public string Color { get; set; } = "#4F46E5";
    public bool IsArchived { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<Transaction> Transactions { get; set; } = [];
}

public class Transaction
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid AccountId { get; set; }
    public Account? Account { get; set; }
    /// <summary>Provider-side id used for idempotent upserts during sync/import.</summary>
    public string? ExternalId { get; set; }
    /// <summary>Signed amount in the account currency. Negative = money out.</summary>
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "PLN";
    public string Description { get; set; } = "";
    public string? CounterParty { get; set; }
    /// <summary>Counterparty IBAN when the bank provides it — used for internal-transfer detection.</summary>
    public string? CounterIban { get; set; }
    public int? Mcc { get; set; }
    public Guid? CategoryId { get; set; }
    public Category? Category { get; set; }
    public List<Tag> Tags { get; set; } = [];
    public DateTime OccurredAt { get; set; }
    public string Source { get; set; } = TransactionSources.Manual;
    public string? Note { get; set; }
    /// <summary>Manually excluded from all statistics.</summary>
    public bool IsExcluded { get; set; }
    /// <summary>Transfer between the user's own accounts — visible, but never counted in metrics.</summary>
    public bool IsInternal { get; set; }
    /// <summary>Links the two legs of a detected internal transfer.</summary>
    public Guid? TransferGroupId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class Category
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Emoji { get; set; } = "🏷️";
    public string Color { get; set; } = "#64748B";
    public string Kind { get; set; } = CategoryKinds.Expense; // expense | income | investment
    public List<Transaction> Transactions { get; set; } = [];
    public List<CategoryRule> Rules { get; set; } = [];
}

public class Tag
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Color { get; set; } = "#0EA5E9";
    public List<Transaction> Transactions { get; set; } = [];
}

public class BankConnection
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Provider { get; set; } = ""; // monobank | enablebanking
    public string DisplayName { get; set; } = "";
    /// <summary>Provider-specific settings (token, keys, session) as JSON.</summary>
    public string SettingsJson { get; set; } = "{}";
    public string Status { get; set; } = "pending"; // pending | linked | error
    public DateTime? LastSyncedAt { get; set; }
    public string? LastError { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<Account> Accounts { get; set; } = [];
}

/// <summary>Keyword rule applied to uncategorized transactions on ingest.</summary>
public class CategoryRule
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Pattern { get; set; } = ""; // case-insensitive "contains" match on description/counterparty
    public Guid CategoryId { get; set; }
    public Category? Category { get; set; }
    public int Priority { get; set; }
}

public class SyncLog
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTime At { get; set; } = DateTime.UtcNow;
    public string Provider { get; set; } = "";
    public string Message { get; set; } = "";
    public bool Success { get; set; } = true;
    public int NewTransactions { get; set; }
}
