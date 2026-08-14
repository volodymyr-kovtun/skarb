using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Meta;

/// <summary>Combined lookup data for filter dropdowns and forms.</summary>
public class MetaEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        app.MapGet("/api/meta", async (SkarbDbContext db) => new
        {
            accounts = await db.Accounts.OrderBy(a => a.CreatedAt).Select(a => a.ToDto()).ToListAsync(),
            categories = await db.Categories.OrderBy(c => c.Kind).ThenBy(c => c.Name).Select(c => c.ToDto()).ToListAsync(),
            tags = await db.Tags.OrderBy(t => t.Name).Select(t => t.ToDto()).ToListAsync(),
        });
    }
}
