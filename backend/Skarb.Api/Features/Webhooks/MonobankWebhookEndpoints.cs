using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Infrastructure.Banking.Monobank;

namespace Skarb.Api.Features.Webhooks;

/// <summary>
/// Receives Monobank push notifications. Must always answer 200 quickly —
/// three failed deliveries and Monobank disables the webhook.
/// </summary>
public class MonobankWebhookEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        // Validation ping: Monobank sends GET and requires exactly HTTP 200.
        app.MapGet("/api/webhooks/monobank/{connectionId:guid}", () => Results.Ok());

        app.MapPost("/api/webhooks/monobank/{connectionId:guid}",
            async (Guid connectionId, HttpRequest request, SkarbDbContext db,
                   ITransactionIngestor ingestor, ITransferDetector transferDetector) =>
        {
            using var doc = await JsonDocument.ParseAsync(request.Body);
            if (!doc.RootElement.TryGetProperty("data", out var data)) return Results.Ok();

            var accountExternalId = data.GetProperty("account").GetString();
            var account = await db.Accounts.FirstOrDefaultAsync(a =>
                a.ConnectionId == connectionId && a.ExternalId == accountExternalId);
            if (account is null) return Results.Ok();

            var item = data.GetProperty("statementItem");
            var incoming = MonobankProvider.MapStatementItem(item, account.Currency, TransactionSources.Webhook);
            await ingestor.IngestAsync(account, [incoming], CancellationToken.None);

            if (item.TryGetProperty("balance", out var bal))
            {
                account.Balance = bal.GetInt64() / 100m - account.CreditLimit;
                await db.SaveChangesAsync();
            }

            await transferDetector.DetectAsync(CancellationToken.None);
            return Results.Ok();
        });
    }
}
