using Skarb.Api.Common.Domain;

namespace Skarb.Api.Common.Contracts;

public record CategoryDto(Guid Id, string Name, string Emoji, string Color, string Kind);
public record TagDto(Guid Id, string Name, string Color);

public record AccountDto(
    Guid Id, string Name, string Bank, string Provider, string Currency,
    decimal Balance, string? Iban, string? MaskedPan, string Color,
    bool IsArchived, bool IsExcluded, Guid? ConnectionId);

public record TransactionDto(
    Guid Id, Guid AccountId, string AccountName, string AccountColor, string Bank,
    decimal Amount, string Currency, string Description, string? CounterParty,
    int? Mcc, CategoryDto? Category, List<TagDto> Tags, DateTime OccurredAt,
    string Source, string? Note, bool IsExcluded, bool IsInternal);

public record PagedResult<T>(List<T> Items, int Total, int Page, int PageSize);

public static class Map
{
    public static CategoryDto ToDto(this Category c) => new(c.Id, c.Name, c.Emoji, c.Color, c.Kind);
    public static TagDto ToDto(this Tag t) => new(t.Id, t.Name, t.Color);

    public static AccountDto ToDto(this Account a) => new(
        a.Id, a.Name, a.Bank, a.Provider, a.Currency, a.Balance,
        a.Iban, a.MaskedPan, a.Color, a.IsArchived, a.IsExcluded, a.ConnectionId);

    public static TransactionDto ToDto(this Transaction t) => new(
        t.Id, t.AccountId, t.Account?.Name ?? "", t.Account?.Color ?? "#64748B",
        t.Account?.Bank ?? "", t.Amount, t.Currency, t.Description, t.CounterParty,
        t.Mcc, t.Category?.ToDto(), t.Tags.Select(x => x.ToDto()).ToList(),
        t.OccurredAt, t.Source, t.Note, t.IsExcluded, t.IsInternal);
}
