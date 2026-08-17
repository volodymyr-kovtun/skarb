using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Infrastructure.Banking.EnableBanking;
using Skarb.Api.Infrastructure.Banking.Monobank;

namespace Skarb.Api.Features.Connections;

public record ConnectionDto(
    Guid Id, string Provider, string DisplayName, string Status,
    DateTime? LastSyncedAt, string? LastError, int AccountCount, DateTime? ConsentValidUntil);

public record MonobankConnectRequest(string Token);
public record MonobankWebhookRequest(string PublicBaseUrl);
public record EnableBankingConnectRequest(string DisplayName, string ApplicationId, string PrivateKeyPem);
public record EnableBankingAuthorizeRequest(string AspspName, string AspspCountry, string RedirectUrl);
public record EnableBankingCompleteRequest(string Code);

public class ConnectionEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/connections");

        group.MapGet("/", async (SkarbDbContext db) =>
        {
            var connections = await db.Connections.OrderBy(c => c.CreatedAt)
                .Select(c => new { Conn = c, AccountCount = c.Accounts.Count })
                .ToListAsync();
            return connections.Select(x =>
            {
                DateTime? validUntil = null;
                if (x.Conn.Provider == ProviderNames.EnableBanking)
                    validUntil = EnableBankingSettings.From(x.Conn).ValidUntil;
                return new ConnectionDto(x.Conn.Id, x.Conn.Provider, x.Conn.DisplayName, x.Conn.Status,
                    x.Conn.LastSyncedAt, x.Conn.LastError, x.AccountCount, validUntil);
            });
        });

        group.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db) =>
        {
            var conn = await db.Connections.FindAsync(id);
            if (conn is null) return Results.NotFound();
            db.Connections.Remove(conn); // accounts stay (FK set to null), history is preserved
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        // ---------- Monobank ----------
        group.MapPost("/monobank", async (MonobankConnectRequest req, SkarbDbContext db, ISyncService sync) =>
        {
            if (string.IsNullOrWhiteSpace(req.Token))
                return Results.BadRequest(new { error = "Token is required" });

            var conn = new BankConnection
            {
                Provider = ProviderNames.Monobank,
                DisplayName = "Monobank",
                Status = ConnectionStatuses.Linked,
            };
            new MonobankSettings { Token = req.Token.Trim() }.SaveTo(conn);
            db.Connections.Add(conn);
            await db.SaveChangesAsync();
            await sync.TriggerAsync(conn.Id);
            return Results.Created($"/api/connections/{conn.Id}", new { conn.Id });
        });

        group.MapPost("/{id:guid}/monobank/webhook",
            async (Guid id, MonobankWebhookRequest req, SkarbDbContext db, MonobankApiClient mono) =>
        {
            var conn = await db.Connections.FirstOrDefaultAsync(c => c.Id == id && c.Provider == ProviderNames.Monobank);
            if (conn is null) return Results.NotFound();
            var settings = MonobankSettings.From(conn);
            var url = $"{req.PublicBaseUrl.TrimEnd('/')}/api/webhooks/monobank/{conn.Id}";
            await mono.SetWebhookAsync(settings.Token, url, CancellationToken.None);
            return Results.Ok(new { webhookUrl = url });
        });

        // ---------- Enable Banking ----------
        group.MapPost("/enablebanking", async (EnableBankingConnectRequest req, SkarbDbContext db) =>
        {
            var conn = new BankConnection
            {
                Provider = ProviderNames.EnableBanking,
                DisplayName = string.IsNullOrWhiteSpace(req.DisplayName) ? "Bank" : req.DisplayName,
            };
            new EnableBankingSettings
            {
                ApplicationId = req.ApplicationId.Trim(),
                PrivateKeyPem = req.PrivateKeyPem.Trim(),
            }.SaveTo(conn);
            db.Connections.Add(conn);
            await db.SaveChangesAsync();
            return Results.Created($"/api/connections/{conn.Id}", new { conn.Id });
        });

        group.MapGet("/{id:guid}/enablebanking/aspsps",
            async (Guid id, SkarbDbContext db, EnableBankingApiClient eb, string? country) =>
        {
            var conn = await db.Connections.FindAsync(id);
            if (conn is null) return Results.NotFound();
            // No country (or "ALL") lists every institution Enable Banking supports.
            var effective = string.IsNullOrWhiteSpace(country) || country == "ALL" ? null : country;
            using var doc = await eb.GetAspspsAsync(EnableBankingSettings.From(conn), effective, CancellationToken.None);
            var list = doc.RootElement.GetProperty("aspsps").EnumerateArray()
                .Select(a => new
                {
                    name = a.GetProperty("name").GetString(),
                    country = a.TryGetProperty("country", out var c) ? c.GetString() : effective,
                    logo = a.TryGetProperty("logo", out var l) ? l.GetString() : null,
                })
                .ToList();
            return Results.Ok(list);
        });

        group.MapPost("/{id:guid}/enablebanking/authorize",
            async (Guid id, EnableBankingAuthorizeRequest req, SkarbDbContext db, EnableBankingApiClient eb,
                   ILogger<ConnectionEndpoints> log) =>
        {
            var conn = await db.Connections.FindAsync(id);
            if (conn is null) return Results.NotFound();
            log.LogInformation("Enable Banking authorize: bank={Bank}/{Country} redirect={Redirect}",
                req.AspspName, req.AspspCountry, req.RedirectUrl);
            var settings = EnableBankingSettings.From(conn);
            settings.AspspName = req.AspspName;
            settings.AspspCountry = req.AspspCountry;
            settings.SaveTo(conn);
            await db.SaveChangesAsync();

            var url = await eb.StartAuthAsync(settings, req.AspspName, req.AspspCountry,
                req.RedirectUrl, conn.Id.ToString(), CancellationToken.None);
            return Results.Ok(new { url });
        });

        group.MapPost("/{id:guid}/enablebanking/complete",
            async (Guid id, EnableBankingCompleteRequest req, SkarbDbContext db,
                   EnableBankingProvider eb, ISyncService sync) =>
        {
            var conn = await db.Connections.FindAsync(id);
            if (conn is null) return Results.NotFound();
            await eb.CompleteAuthAsync(conn, req.Code, CancellationToken.None);
            await sync.TriggerAsync(conn.Id);
            return Results.Ok(new { status = conn.Status });
        });
    }
}
