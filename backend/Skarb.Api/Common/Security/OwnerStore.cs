using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Common.Security;

/// <summary>EF-backed <see cref="IOwnerStore"/>. The only place auth code knows a database exists.</summary>
public sealed class OwnerStore(SkarbDbContext db) : IOwnerStore
{
    public Task<OwnerAccount?> GetAsync(CancellationToken ct = default) =>
        db.Owners.Include(o => o.RecoveryCodes).OrderBy(o => o.CreatedAt).FirstOrDefaultAsync(ct);

    public Task<bool> ExistsAsync(CancellationToken ct = default) => db.Owners.AnyAsync(ct);

    /// <summary>The owner is change-tracked by this store, so saving is just flushing it.</summary>
    public Task SaveAsync(OwnerAccount owner, CancellationToken ct = default) => db.SaveChangesAsync(ct);

    public async Task<OwnerAccount> CreateAsync(OwnerAccount owner, CancellationToken ct = default)
    {
        // Setup that was started but never confirmed leaves an unusable row behind; replacing
        // it lets the owner simply run setup again rather than reach for psql.
        var abandoned = await db.Owners.Include(o => o.RecoveryCodes).ToListAsync(ct);
        db.Owners.RemoveRange(abandoned);

        db.Owners.Add(owner);
        await db.SaveChangesAsync(ct);
        return owner;
    }
}
