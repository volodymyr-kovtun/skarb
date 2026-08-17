using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Import;

public record CsvImportRequest(
    Guid AccountId, string Content,
    int DateColumn, int AmountColumn, int DescriptionColumn, int? CurrencyColumn,
    string? DateFormat, string? DecimalSeparator, string? Delimiter, bool HasHeader, bool InvertAmount);

public class CsvImportEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        app.MapPost("/api/import/csv",
            async (CsvImportRequest req, SkarbDbContext db, CsvImportService csv, ITransferDetector transferDetector) =>
        {
            var account = await db.Accounts.FindAsync(req.AccountId);
            if (account is null) return Results.BadRequest(new { error = "Account not found" });

            var result = await csv.ImportAsync(account, req, CancellationToken.None);
            await transferDetector.DetectAsync(CancellationToken.None);
            return Results.Ok(result);
        });
    }
}
