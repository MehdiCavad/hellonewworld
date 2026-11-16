using Rankd.Core.Ranking;

namespace Rankd.Core.Catalogue;

/// <summary>Shape of shared/catalogue.json, the launch catalogue carried over from the prototype.</summary>
public sealed record SeedCatalogue(IReadOnlyList<SeedLevel> Levels, IReadOnlyList<SeedTopic> Topics);

public sealed record SeedLevel(string Id, string Name, string Emoji, IReadOnlyList<int> Tiers, int PoolSize, int RoundBudget, string Blurb);

public sealed record SeedTopic(string Slug, string Name, string Emoji, string Blurb, string MediaKind, IReadOnlyList<SeedItem> Items);

public sealed record SeedItem(string Name, string Detail, int Tier, string? Wiki);

public static class Pools
{
    /// <summary>
    /// Picks the pool for a topic and level: filter by unlocked tiers, then take
    /// the most prominent items first (tier order), shuffled inside each tier so
    /// repeat sessions differ.
    /// </summary>
    public static List<T> Build<T>(IEnumerable<T> items, Func<T, int> tierOf, IReadOnlyList<int> tiers, int poolSize, Func<double> random)
    {
        var ordered = new List<T>();
        foreach (var group in items.Where(i => tiers.Contains(tierOf(i))).GroupBy(tierOf).OrderBy(g => g.Key))
        {
            var bucket = group.ToList();
            for (int i = bucket.Count - 1; i > 0; i--)
            {
                int j = (int)Math.Floor(random() * (i + 1));
                (bucket[i], bucket[j]) = (bucket[j], bucket[i]);
            }
            ordered.AddRange(bucket);
        }
        return poolSize > 0 ? ordered.Take(poolSize).ToList() : ordered;
    }

    /// <summary>Rounds for a level; a level without a fixed budget is sized to the pool.</summary>
    public static int RoundsFor(int roundBudget, int poolSize) =>
        roundBudget > 0 ? Math.Min(roundBudget, RankingEngine.MaxUsefulRounds(poolSize)) : RankingEngine.MaxUsefulRounds(poolSize);
}
