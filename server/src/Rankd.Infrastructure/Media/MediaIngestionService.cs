using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Rankd.Core.Domain;
using Rankd.Infrastructure.Data;
using Rankd.Infrastructure.Services;

namespace Rankd.Infrastructure.Media;

public sealed record IngestionResult(int ItemsChecked, int AssetsAdded, int AssetsUpdated, IReadOnlyList<string> Errors);

/// <summary>
/// Pulls media references for a topic's items from its provider and records
/// them with provenance. Assets an admin has disabled are never re-enabled.
/// </summary>
public sealed class MediaIngestionService(
    RankdDbContext db, IHttpClientFactory httpFactory, IEnumerable<IMediaProvider> providers,
    AuditLogger audit, TimeProvider clock, ILogger<MediaIngestionService> log)
{
    public const string HttpClientName = "media";

    public async Task<IngestionResult> IngestTopicAsync(int topicId, bool onlyMissing, CancellationToken ct = default)
    {
        var topic = await db.Topics.FirstAsync(t => t.Id == topicId, ct);
        var items = await db.Items.Include(i => i.Assets).Where(i => i.TopicId == topicId && i.IsActive).ToListAsync(ct);
        if (onlyMissing) items = items.Where(i => i.Assets.All(a => a.Type != AssetType.Image)).ToList();
        var result = await IngestAsync(topic, items, ct);
        await audit.LogAsync("media.ingest", topic.Name,
            $"{result.ItemsChecked} items checked, {result.AssetsAdded} added, {result.AssetsUpdated} updated, {result.Errors.Count} errors", ct);
        return result;
    }

    public async Task<IngestionResult> IngestItemAsync(int itemId, CancellationToken ct = default)
    {
        var item = await db.Items.Include(i => i.Assets).Include(i => i.Topic).FirstAsync(i => i.Id == itemId, ct);
        var result = await IngestAsync(item.Topic!, [item], ct);
        await audit.LogAsync("media.rematch", item.Name, $"{result.AssetsAdded} added, {result.AssetsUpdated} updated", ct);
        return result;
    }

    private async Task<IngestionResult> IngestAsync(Topic topic, List<Item> items, CancellationToken ct)
    {
        var provider = providers.FirstOrDefault(p => p.Supports(topic.MediaKind));
        if (provider is null || items.Count == 0) return new IngestionResult(items.Count, 0, 0, []);

        var http = httpFactory.CreateClient(HttpClientName);
        var errors = new List<string>();
        int added = 0, updated = 0;

        foreach (var batch in items.Chunk(provider.BatchSize))
        {
            IReadOnlyList<MediaCandidate> found;
            try
            {
                found = await provider.FindAsync(http, topic, batch, ct);
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
            {
                log.LogWarning(ex, "{Provider} lookup failed for {Items}", provider.Name, string.Join(", ", batch.Select(i => i.Name)));
                errors.Add($"{string.Join(", ", batch.Select(i => i.Name))}: {ex.Message}");
                await Task.Delay(provider.Spacing, ct);
                continue;
            }

            foreach (var c in found)
            {
                var item = batch.First(i => i.Id == c.ItemId);
                var existing = item.Assets.FirstOrDefault(a => a.Type == c.Type && a.Provider == c.Provider);
                if (existing is null)
                {
                    item.Assets.Add(ToAsset(c));
                    added++;
                }
                else if (existing.IsEnabled && existing.Url != c.Url)
                {
                    existing.Url = c.Url;
                    existing.ProviderId = c.ProviderId;
                    existing.SourceUrl = c.SourceUrl;
                    existing.Licence = c.Licence;
                    existing.Attribution = c.Attribution;
                    existing.RetrievedAt = clock.GetUtcNow();
                    updated++;
                }
                item.UpdatedAt = clock.GetUtcNow();
            }
            await db.SaveChangesAsync(ct);
            await Task.Delay(provider.Spacing, ct);
        }

        topic.UpdatedAt = clock.GetUtcNow();
        await db.SaveChangesAsync(ct);
        return new IngestionResult(items.Count, added, updated, errors);
    }

    private Asset ToAsset(MediaCandidate c) => new()
    {
        ItemId = c.ItemId, Type = c.Type, Url = c.Url, Provider = c.Provider, ProviderId = c.ProviderId,
        SourceUrl = c.SourceUrl, Licence = c.Licence, Attribution = c.Attribution, HotlinkOnly = true,
        RetrievedAt = clock.GetUtcNow(), IsEnabled = true,
    };
}
