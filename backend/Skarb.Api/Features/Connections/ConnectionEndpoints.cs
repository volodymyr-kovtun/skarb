using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Infrastructure.Banking.EnableBanking;
using Skarb.Api.Infrastructure.Banking.Monobank;

namespace Skarb.Api.Features.Connections;

public record ConnectionDto(
    Guid Id, string Provider, string DisplayName, string Status,
    DateTime? LastSyncedAt, string? LastError, int AccountCount, DateTime? ConsentValidUntil,
    int IgnoredAccountCount);

public record UpdateConnectionRequest(string DisplayName);
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
            return connections.Select(x => ToDto(x.Conn, x.AccountCount));
        });

        group.MapPatch("/{id:guid}", async (Guid id, UpdateConnectionRequest req, SkarbDbContext db) =>
        {
            var conn = await db.Connections.Include(c => c.Accounts).FirstOrDefaultAsync(c => c.Id == id);
            if (conn is null) return Results.NotFound();
            var name = req.DisplayName?.Trim();
            if (string.IsNullOrWhiteSpace(name))
                return Results.BadRequest(new { error = "Name is required" });
            // The institution shown on an account is this name, so carry the rename over and
            // grouping by bank follows it everywhere. Every account goes, not just the ones
            // still matching the old name — one whose label had drifted would otherwise be
            // stranded, skipped by this rename and by every rename after it.
            foreach (var account in conn.Accounts)
                account.Bank = name;
            conn.DisplayName = name;
            await db.SaveChangesAsync();
            return Results.Ok(ToDto(conn, conn.Accounts.Count));
        });

        group.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db) =>
        {
            var conn = await db.Connections.Include(c => c.Accounts).FirstOrDefaultAsync(c => c.Id == id);
            if (conn is null) return Results.NotFound();
            // The accounts exist only because this connection created them, so they go with it —
            // their transactions cascade. Manually created accounts are never linked to a connection.
            db.Accounts.RemoveRange(conn.Accounts);
            db.Connections.Remove(conn);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        // Forgetting the deleted accounts is the only way back — the next sync rediscovers
        // them from the bank, with their history re-fetched from scratch.
        group.MapPost("/{id:guid}/ignored/restore", async (Guid id, SkarbDbContext db, ISyncService sync) =>
        {
            var conn = await db.Connections.FindAsync(id);
            if (conn is null) return Results.NotFound();
            var restored = conn.IgnoredExternalIds.Count;
            conn.IgnoredExternalIds = [];
            await db.SaveChangesAsync();
            if (restored > 0) await sync.TriggerAsync(conn.Id);
            return Results.Ok(new { restored });
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

    private static ConnectionDto ToDto(BankConnection conn, int accountCount)
    {
        DateTime? validUntil = conn.Provider == ProviderNames.EnableBanking
            ? EnableBankingSettings.From(conn).ValidUntil
            : null;
        return new ConnectionDto(conn.Id, conn.Provider, conn.DisplayName, conn.Status,
            conn.LastSyncedAt, conn.LastError, accountCount, validUntil, conn.IgnoredExternalIds.Count);
    }
}
