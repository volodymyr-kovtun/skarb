using Skarb.Api.Common.Abstractions;

namespace Skarb.Api.Common.Endpoints;

public static class EndpointGroupExtensions
{
    /// <summary>Discovers and maps every IEndpointGroup in the assembly (Carter-style vertical slices).</summary>
    public static void MapEndpointGroups(this WebApplication app)
    {
        var groups = typeof(EndpointGroupExtensions).Assembly.GetTypes()
            .Where(t => t.IsAssignableTo(typeof(IEndpointGroup)) && t is { IsClass: true, IsAbstract: false })
            .Select(Activator.CreateInstance)
            .Cast<IEndpointGroup>();
        foreach (var group in groups)
            group.Map(app);
    }
}
