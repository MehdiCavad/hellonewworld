using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Rankd.Core.Catalogue;
using Rankd.Core.Domain;
using Rankd.Infrastructure.Data;

namespace Rankd.Infrastructure.Services;

/// <summary>Loads shared/catalogue.json (the prototype's launch catalogue) into an empty database.</summary>
public sealed class CatalogueSeeder(RankdDbContext db)
{
    private static readonly Dictionary<string, string> Accents = new()
    {
        ["movies"] = "#FF5D5D",
        ["actors"] = "#B26BFF",
        ["footballers"] = "#22C55E",
        ["music"] = "#F59E0B",
        ["songs"] = "#F0499B",
        ["food"] = "#FF8A3D",
        ["languages"] = "#3B82F6",
        ["cities"] = "#14B8A6",
        ["series"] = "#7C5CFF",
    };

    public static SeedCatalogue Load()
    {
        using var stream = typeof(CatalogueSeeder).Assembly.GetManifestResourceStream("catalogue.json")
                           ?? throw new InvalidOperationException("Embedded catalogue.json is missing.");
        return JsonSerializer.Deserialize<SeedCatalogue>(stream, new JsonSerializerOptions(JsonSerializerDefaults.Web))
               ?? throw new InvalidOperationException("catalogue.json is empty.");
    }

    public async Task<int> SeedAsync(CancellationToken ct = default)
    {
        var catalogue = Load();

        var levelIds = await db.Levels.Select(l => l.Id).ToListAsync(ct);
        int order = 0;
        foreach (var l in catalogue.Levels)
        {
            order++;
            if (levelIds.Contains(l.Id)) continue;
            db.Levels.Add(new Level
            {
                Id = l.Id, Name = l.Name, Emoji = l.Emoji, Description = l.Blurb,
                Tiers = string.Join(',', l.Tiers), PoolSize = l.PoolSize, RoundBudget = l.RoundBudget, SortOrder = order,
            });
        }

        var slugs = await db.Topics.Select(t => t.Slug).ToListAsync(ct);
        int added = 0;
        order = 0;
        foreach (var t in catalogue.Topics)
        {
            order++;
            if (slugs.Contains(t.Slug)) continue;
            db.Topics.Add(new Topic
            {
                Slug = t.Slug, Name = t.Name, Emoji = t.Emoji, Description = t.Blurb, MediaKind = t.MediaKind,
                Accent = Accents.GetValueOrDefault(t.Slug, "#7C5CFF"), SortOrder = order,
                Items = t.Items.Select(i => new Item
                {
                    Name = i.Name, Detail = i.Detail, Tier = i.Tier,
                    WikiTitle = string.IsNullOrWhiteSpace(i.Wiki) ? null : i.Wiki,
                }).ToList(),
            });
            added++;
        }

        await db.SaveChangesAsync(ct);
        return added;
    }
}
