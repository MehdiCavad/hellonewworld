using Microsoft.EntityFrameworkCore;
using Rankd.Core.Domain;
using Rankd.Infrastructure.Contracts;
using Rankd.Infrastructure.Data;

namespace Rankd.Api.Endpoints;

public static class CatalogueEndpoints
{
    public static RouteGroupBuilder MapCatalogue(this RouteGroupBuilder api)
    {
        api.MapGet("/levels", async (RankdDbContext db, CancellationToken ct) =>
                (await db.Levels.AsNoTracking().OrderBy(l => l.SortOrder).ToListAsync(ct))
                .Select(l => new LevelDto(l.Id, l.Name, l.Emoji, l.Description, l.TierList, l.PoolSize, l.RoundBudget)))
            .WithName("ListLevels").WithSummary("Difficulty levels: pool size, unlocked tiers and round budget.")
            .CacheOutput("catalogue");

        api.MapGet("/topics", async (RankdDbContext db, CancellationToken ct) =>
            {
                var topics = await db.Topics.AsNoTracking().Where(t => t.IsActive).OrderBy(t => t.SortOrder).ToListAsync(ct);
                var tiers = await db.Items.Where(i => i.IsActive).GroupBy(i => new { i.TopicId, i.Tier })
                    .Select(g => new { g.Key.TopicId, g.Key.Tier, Count = g.Count(), Updated = g.Max(i => i.UpdatedAt) })
                    .ToListAsync(ct);
                // One cover per topic: the first enabled image among its household names.
                var covers = (await db.Assets.Where(a => a.IsEnabled && a.Type == AssetType.Image && a.Item!.IsActive && a.Item.Tier == 1)
                        .OrderBy(a => a.ItemId).Select(a => new { a.Item!.TopicId, a.Url }).ToListAsync(ct))
                    .GroupBy(a => a.TopicId).ToDictionary(g => g.Key, g => g.First().Url);

                return topics.Select(t =>
                {
                    var mine = tiers.Where(x => x.TopicId == t.Id).ToList();
                    return new TopicSummaryDto(t.Slug, t.Name, t.Emoji, t.Description, t.MediaKind, t.Accent,
                        mine.Sum(x => x.Count), mine.ToDictionary(x => x.Tier, x => x.Count), covers.GetValueOrDefault(t.Id),
                        Max(t.UpdatedAt, mine.Count == 0 ? null : mine.Max(x => x.Updated)));
                });
            })
            .WithName("ListTopics").WithSummary("Active topics with item counts per tier.")
            .CacheOutput("catalogue");

        api.MapGet("/topics/{slug}", async (string slug, RankdDbContext db, HttpContext http, CancellationToken ct) =>
            {
                var topic = await db.Topics.AsNoTracking()
                    .Include(t => t.Items.Where(i => i.IsActive)).ThenInclude(i => i.Assets.Where(a => a.IsEnabled))
                    .AsSplitQuery()
                    .FirstOrDefaultAsync(t => t.Slug == slug && t.IsActive, ct);
                if (topic is null) return Results.NotFound(new ApiProblem("Topic not found", $"No active topic '{slug}'."));

                var updated = Max(topic.UpdatedAt, topic.Items.Count == 0 ? null : topic.Items.Max(i => i.UpdatedAt));
                // Lets the app keep its offline copy until something actually changes.
                var etag = $"\"{slug}-{updated.ToUnixTimeMilliseconds()}-{topic.Items.Count}-{topic.Items.Sum(i => i.Assets.Count)}\"";
                if (http.Request.Headers.IfNoneMatch == etag) return Results.StatusCode(StatusCodes.Status304NotModified);
                http.Response.Headers.ETag = etag;

                return Results.Ok(new TopicDetailDto(topic.Slug, topic.Name, topic.Emoji, topic.Description, topic.MediaKind,
                    topic.Accent, updated,
                    topic.Items.OrderBy(i => i.Tier).ThenBy(i => i.Name)
                        .Select(i => new ItemDto(i.Id, i.Name, i.Detail, i.Tier,
                            ToMedia(i.Assets.FirstOrDefault(a => a.Type == AssetType.Image)),
                            ToMedia(i.Assets.FirstOrDefault(a => a.Type == AssetType.Audio))))
                        .ToList()));
            })
            .WithName("GetTopic").WithSummary("A topic with its items and enabled media, for play and offline download.")
            .Produces<TopicDetailDto>().Produces<ApiProblem>(StatusCodes.Status404NotFound)
            .CacheOutput("catalogue");

        api.MapGet("/attributions", async (RankdDbContext db, CancellationToken ct) =>
            {
                var counts = await db.Assets.Where(a => a.IsEnabled).GroupBy(a => a.Provider)
                    .Select(g => new { Provider = g.Key, Count = g.Count() }).ToListAsync(ct);
                return Attributions.Select(a => a with { Assets = counts.FirstOrDefault(c => c.Provider == a.Provider)?.Count ?? 0 });
            })
            .WithName("ListAttributions").WithSummary("Content providers and the notices the app must show.")
            .CacheOutput("catalogue");

        return api;
    }

    private static readonly ProviderAttributionDto[] Attributions =
    [
        new("Wikimedia Commons", "Photos are freely licensed works by their authors, credited on each item.", "https://commons.wikimedia.org", 0),
        new("Apple iTunes", "Artwork and 30-second previews courtesy of Apple. Tap through to the store to hear more.", "https://www.apple.com/itunes/", 0),
        new("TMDB", "This product uses the TMDB API but is not endorsed or certified by TMDB.", "https://www.themoviedb.org", 0),
    ];

    public static MediaDto? ToMedia(Asset? a) => a is null ? null
        : new MediaDto(a.Type == AssetType.Image ? "image" : "audio", a.Url, a.Provider, a.SourceUrl, a.Licence, a.Attribution);

    private static DateTimeOffset Max(DateTimeOffset a, DateTimeOffset? b) => b is { } v && v > a ? v : a;
}
