using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Contracts;
using Skarb.Api.Common.Domain;
using Skarb.Api.Common.Persistence;

namespace Skarb.Api.Features.Tags;

public record CreateTagRequest(string Name, string? Color);
public record UpdateTagRequest(string? Name, string? Color);

public class TagEndpoints : IEndpointGroup
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/tags");

        group.MapPost("/", async (CreateTagRequest req, SkarbDbContext db) =>
        {
            var name = req.Name.Trim().ToLowerInvariant();
            if (name.Length == 0) return Results.BadRequest(new { error = "Name is required." });
            var existing = await db.Tags.FirstOrDefaultAsync(t => t.Name == name);
            if (existing is not null) return Results.Ok(existing.ToDto());
            var tag = new Tag { Name = name };
            if (req.Color is not null) tag.Color = req.Color;
            db.Tags.Add(tag);
            await db.SaveChangesAsync();
            return Results.Created($"/api/tags/{tag.Id}", tag.ToDto());
        });

        group.MapPatch("/{id:guid}", async (Guid id, UpdateTagRequest req, SkarbDbContext db) =>
        {
            var tag = await db.Tags.FindAsync(id);
            if (tag is null) return Results.NotFound();

            if (req.Name is not null)
            {
                var name = req.Name.Trim().ToLowerInvariant();
                if (name.Length == 0) return Results.BadRequest(new { error = "Name is required." });
                if (await db.Tags.AnyAsync(t => t.Id != id && t.Name == name))
                    return Results.BadRequest(new { error = $"A tag called \"{name}\" already exists." });
                tag.Name = name;
            }
            if (req.Color is not null) tag.Color = req.Color;

            await db.SaveChangesAsync();
            return Results.Ok(tag.ToDto());
        });

        group.MapDelete("/{id:guid}", async (Guid id, SkarbDbContext db) =>
        {
            var tag = await db.Tags.FindAsync(id);
            if (tag is null) return Results.NotFound();
            db.Tags.Remove(tag);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });
    }
}
