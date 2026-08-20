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

public static class ConnectionStatuses
{
    public const string Pending = "pending";
    public const string Linked = "linked";
    public const string Error = "error";
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
    /// <summary>
    /// Closed and put away: hidden from the overview, skipped by sync, and folded into
    /// the archived section of the accounts page.
    /// </summary>
    public bool IsArchived { get; set; }
    /// <summary>
    /// Kept out of the owner's picture while staying a live account: it still syncs, and the
    /// accounts page still reports its balance, but it counts toward nothing on the overview
    /// and its transactions stay out of the transaction list. For money you hold but don't
    /// consider yours to spend.
    /// </summary>
    public bool IsExcluded { get; set; }
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
    /// <summary>Bank-supplied transaction type code (e.g. "CARD-ATM", "MOBILE-PAYMENT-C2C"), when available.</summary>
    public string? TypeCode { get; set; }
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
    /// <summary>Stable identifier for seeded categories (MCC mapping targets this, so renaming is safe).</summary>
    public string? SystemKey { get; set; }
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
    public string Status { get; set; } = ConnectionStatuses.Pending;
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

/// <summary>
/// The single person who owns this Skarb instance. Skarb is deliberately single-tenant:
/// there is at most one row, created once through the first-run setup flow.
/// </summary>
public class OwnerAccount
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Email { get; set; } = "";
    /// <summary>Opaque, versioned hash produced by <c>IPasswordHasher</c> — never a raw digest.</summary>
    public string PasswordHash { get; set; } = "";
    /// <summary>Base32 TOTP shared secret (RFC 4648), as handed to the authenticator app.</summary>
    public string TotpSecret { get; set; } = "";
    /// <summary>False until the owner proves they can generate a code, so setup can't lock them out.</summary>
    public bool TotpEnabled { get; set; }
    /// <summary>Highest TOTP time-step already accepted — blocks replay of an observed code.</summary>
    public long LastTotpStep { get; set; }
    /// <summary>Changes whenever credentials change; live cookies carrying an old stamp are rejected.</summary>
    public string SecurityStamp { get; set; } = Guid.NewGuid().ToString("N");
    public int FailedAttempts { get; set; }
    public DateTime? LockedUntil { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastLoginAt { get; set; }
    public List<RecoveryCode> RecoveryCodes { get; set; } = [];
}

/// <summary>Single-use fallback for a lost authenticator. Stored hashed, like a password.</summary>
public class RecoveryCode
{
    /// <remarks>
    /// Deliberately not pre-seeded with a Guid, unlike the other entities here. These are
    /// created by adding them to <see cref="OwnerAccount.RecoveryCodes"/> on an already-tracked
    /// owner, and EF decides insert-vs-update for such children by whether the key is set —
    /// a pre-set key would make it try to UPDATE rows that do not exist yet.
    /// </remarks>
    public Guid Id { get; set; }
    public Guid OwnerId { get; set; }
    public OwnerAccount? Owner { get; set; }
    public string CodeHash { get; set; } = "";
    public DateTime? UsedAt { get; set; }
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
