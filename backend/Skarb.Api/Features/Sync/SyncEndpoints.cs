using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Sync;

public class SyncEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/sync");

        group.MapPost("/", async (ISyncService sync) => new { started = await sync.TriggerAsync() });
        group.MapPost("/{connectionId:guid}", async (Guid connectionId, ISyncService sync) =>
            new { started = await sync.TriggerAsync(connectionId) });

        group.MapGet("/status", async (ISyncService sync, SkarbDbContext db) => new
        {
            running = sync.Running.Values.ToList(),
            logs = await db.SyncLogs.OrderByDescending(l => l.At).Take(20)
                .Select(l => new { l.At, l.Provider, l.Message, l.Success, l.NewTransactions })
                .ToListAsync(),
        });
    }
}
