using System.Collections.Concurrent;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Sync;

/// <summary>
/// Orchestrates syncs across bank connections. Depends only on IBankProvider,
/// so new integrations require zero changes here. Syncs run in the background
/// (Monobank rate limits make them take minutes); the UI polls status.
/// </summary>
public class SyncService(IServiceScopeFactory scopeFactory, ILogger<SyncService> logger) : ISyncService
{
    private readonly ConcurrentDictionary<Guid, string> _running = new();

    public IReadOnlyDictionary<Guid, string> Running => _running;

    public async Task<List<Guid>> TriggerAsync(Guid? connectionId = null)
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SkarbDbContext>();
        var query = db.Connections.Where(c => c.Status != "pending");
        if (connectionId is Guid id) query = query.Where(c => c.Id == id);
        var connections = await query.ToListAsync();

        var started = new List<Guid>();
        foreach (var conn in connections)
        {
            if (!_running.TryAdd(conn.Id, conn.DisplayName)) continue;
            started.Add(conn.Id);
            _ = Task.Run(() => RunOneAsync(conn.Id));
        }
        return started;
    }

    private async Task RunOneAsync(Guid connectionId)
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SkarbDbContext>();
        var providers = scope.ServiceProvider.GetRequiredService<IEnumerable<IBankProvider>>();
        var transferDetector = scope.ServiceProvider.GetRequiredService<ITransferDetector>();

        var conn = await db.Connections.FirstAsync(c => c.Id == connectionId);
        try
        {
            var provider = providers.FirstOrDefault(p => p.Key == conn.Provider)
                ?? throw new InvalidOperationException($"No provider registered for '{conn.Provider}'");

            var result = await provider.SyncAsync(conn, CancellationToken.None);
            await transferDetector.DetectAsync(CancellationToken.None);

            conn.LastSyncedAt = DateTime.UtcNow;
            conn.LastError = null;
            conn.Status = "linked";
            db.SyncLogs.Add(new SyncLog
            {
                Provider = conn.Provider,
                Message = $"{conn.DisplayName}: synced, {result.NewTransactions} new transaction(s)",
                NewTransactions = result.NewTransactions,
            });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Sync failed for {Connection}", conn.DisplayName);
            conn.LastError = ex.Message;
            conn.Status = "error";
            db.SyncLogs.Add(new SyncLog
            {
                Provider = conn.Provider,
                Message = $"{conn.DisplayName}: {ex.Message}",
                Success = false,
            });
        }
        finally
        {
            await db.SaveChangesAsync();
            _running.TryRemove(connectionId, out _);
        }
    }
}

/// <summary>Periodic auto-sync so paid transactions show up without opening the app.</summary>
public class BackgroundSyncService(ISyncService sync, IOptions<SyncOptions> options, ILogger<BackgroundSyncService> logger)
    : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromMinutes(options.Value.IntervalMinutes);
        if (interval <= TimeSpan.Zero) return;

        try
        {
            // Give the app a moment to start before the first sync.
            await Task.Delay(TimeSpan.FromSeconds(15), stoppingToken);

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    await sync.TriggerAsync();
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Background sync trigger failed");
                }
                await Task.Delay(interval, stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
            // normal shutdown
        }
    }
}
