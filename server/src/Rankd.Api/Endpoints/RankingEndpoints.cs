using Microsoft.EntityFrameworkCore;
using Rankd.Core.Domain;
using Rankd.Infrastructure.Contracts;
using Rankd.Infrastructure.Data;

namespace Rankd.Api.Endpoints;

public static class RankingEndpoints
{
    public static RouteGroupBuilder MapRankings(this RouteGroupBuilder api)
    {
        api.MapGet("/topics/{slug}/global-ranking", async (string slug, int? take, RankdDbContext db, CancellationToken ct) =>
            {
                var topic = await db.Topics.AsNoTracking().FirstOrDefaultAsync(t => t.Slug == slug && t.IsActive, ct);
                if (topic is null) return Results.NotFound(new ApiProblem("Topic not found", $"No active topic '{slug}'."));

                var rows = await db.GlobalRankings.AsNoTracking()
                    .Where(g => g.TopicId == topic.Id && g.Item!.IsActive)
                    .OrderBy(g => g.Rank).Take(Math.Clamp(take ?? 100, 1, 500))
                    .Select(g => new
                    {
                        g.Rank, g.PreviousRank, g.ItemId, g.Item!.Name, g.Item.Detail, g.Rating, g.ComparisonCount,
                        g.Wins, g.Losses, g.Ties, g.ComputedAt,
                        Image = g.Item.Assets.Where(a => a.IsEnabled && a.Type == AssetType.Image).FirstOrDefault(),
                    })
                    .ToListAsync(ct);

                var devices = await db.Sessions.Where(s => s.TopicId == topic.Id && !s.Device!.IsBlocked)
                    .Select(s => s.DeviceId).Distinct().CountAsync(ct);

                return Results.Ok(new GlobalRankingDto(slug, rows.FirstOrDefault()?.ComputedAt, devices,
                    rows.Select(r => new GlobalRankingRowDto(r.Rank, r.PreviousRank, r.ItemId, r.Name, r.Detail,
                        Math.Round(r.Rating, 1), r.ComparisonCount, r.Wins, r.Losses, r.Ties, CatalogueEndpoints.ToMedia(r.Image))).ToList()));
            })
            .WithName("GetGlobalRanking").WithSummary("The community ranking for a topic, recomputed in the background.")
            .Produces<GlobalRankingDto>()
            .CacheOutput("catalogue");
        return api;
    }
}
