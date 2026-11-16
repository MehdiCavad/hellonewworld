namespace Rankd.Core.Domain;

/// <summary>How a topic's media are sourced (see scope doc §9.1).</summary>
public static class MediaKinds
{
    public const string Wikipedia = "wikipedia";
    public const string ItunesMovie = "itunes:movie";
    public const string ItunesSong = "itunes:song";
    public const string ItunesTvSeason = "itunes:tvSeason";
    public static readonly string[] All = [Wikipedia, ItunesMovie, ItunesSong, ItunesTvSeason];
}

public sealed class Topic
{
    public int Id { get; set; }
    public required string Slug { get; set; }
    public required string Name { get; set; }
    public string Emoji { get; set; } = "⭐";
    public string Description { get; set; } = "";
    public string MediaKind { get; set; } = MediaKinds.Wikipedia;
    /// <summary>Hex accent used by the app's topic card gradient, e.g. "#7C5CFF".</summary>
    public string Accent { get; set; } = "#7C5CFF";
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public List<Item> Items { get; set; } = new();
}

public sealed class Item
{
    public int Id { get; set; }
    public int TopicId { get; set; }
    public Topic? Topic { get; set; }
    public required string Name { get; set; }
    /// <summary>Year, country or artist: the small line under the name.</summary>
    public string Detail { get; set; } = "";
    /// <summary>1 = household names, 2 = well known, 3 = deeper cuts.</summary>
    public int Tier { get; set; } = 1;
    public string? WikiTitle { get; set; }
    public string? TmdbId { get; set; }
    public string? MusicBrainzId { get; set; }
    public string? WikidataId { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public List<Asset> Assets { get; set; } = new();
}

public enum AssetType { Image = 0, Audio = 1 }

/// <summary>A media reference with its provenance. We hotlink; no files are stored.</summary>
public sealed class Asset
{
    public int Id { get; set; }
    public int ItemId { get; set; }
    public Item? Item { get; set; }
    public AssetType Type { get; set; }
    public required string Url { get; set; }
    public required string Provider { get; set; }
    public string? ProviderId { get; set; }
    /// <summary>Where a user can see the original (article, store page).</summary>
    public string? SourceUrl { get; set; }
    public string Licence { get; set; } = "";
    public string Attribution { get; set; } = "";
    public bool HotlinkOnly { get; set; } = true;
    public DateTimeOffset RetrievedAt { get; set; } = DateTimeOffset.UtcNow;
    /// <summary>The kill switch: disabled assets vanish from the app without a release.</summary>
    public bool IsEnabled { get; set; } = true;
    public string? DisabledReason { get; set; }
}

public sealed class Level
{
    public required string Id { get; set; }
    public required string Name { get; set; }
    public string Emoji { get; set; } = "";
    public string Description { get; set; } = "";
    /// <summary>Comma-separated unlocked tiers, e.g. "1,2".</summary>
    public string Tiers { get; set; } = "1";
    /// <summary>0 = the whole topic.</summary>
    public int PoolSize { get; set; }
    /// <summary>0 = sized to the pool.</summary>
    public int RoundBudget { get; set; }
    public int SortOrder { get; set; }

    public IReadOnlyList<int> TierList =>
        Tiers.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Select(int.Parse).ToArray();
}

/// <summary>Replaces user accounts: a random id the app creates on first launch.</summary>
public sealed class Device
{
    public Guid Id { get; set; }
    public string? Platform { get; set; }
    public string? AppVersion { get; set; }
    public DateTimeOffset FirstSeenAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset LastSeenAt { get; set; } = DateTimeOffset.UtcNow;
    /// <summary>Blocked devices still play locally but stop counting towards global rankings.</summary>
    public bool IsBlocked { get; set; }
}

public enum SessionStatus { Active = 0, Finished = 1, Abandoned = 2 }

public sealed class RankingSessionRecord
{
    public Guid Id { get; set; }
    public Guid DeviceId { get; set; }
    public Device? Device { get; set; }
    public int TopicId { get; set; }
    public Topic? Topic { get; set; }
    public required string LevelId { get; set; }
    public string Mode { get; set; } = "smart";
    public long Seed { get; set; }
    public int TargetRounds { get; set; }
    public SessionStatus Status { get; set; }
    /// <summary>Item ids in the pool, comma-separated.</summary>
    public string PoolItemIds { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public List<Comparison> Comparisons { get; set; } = new();
    public List<PersonalRanking> Rankings { get; set; } = new();
}

public enum ComparisonOutcome { A = 0, B = 1, Tie = 2 }

public sealed class Comparison
{
    public long Id { get; set; }
    public Guid SessionId { get; set; }
    public RankingSessionRecord? Session { get; set; }
    /// <summary>Position in the device's history; makes offline uploads idempotent.</summary>
    public int ClientSequence { get; set; }
    public int ItemAId { get; set; }
    public int ItemBId { get; set; }
    public ComparisonOutcome Outcome { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PersonalRanking
{
    public Guid SessionId { get; set; }
    public int ItemId { get; set; }
    public int Rank { get; set; }
    public double Rating { get; set; }
    public int Wins { get; set; }
    public int Losses { get; set; }
    public int Ties { get; set; }
    public double Confidence { get; set; }
}

public sealed class GlobalRanking
{
    public int TopicId { get; set; }
    public int ItemId { get; set; }
    public Item? Item { get; set; }
    public int Rank { get; set; }
    public double Rating { get; set; }
    public int ComparisonCount { get; set; }
    public int Wins { get; set; }
    public int Losses { get; set; }
    public int Ties { get; set; }
    /// <summary>Rank in the previous snapshot, for the ▲▼ movement arrows.</summary>
    public int? PreviousRank { get; set; }
    public DateTimeOffset ComputedAt { get; set; }
}

public sealed class AuditEntry
{
    public long Id { get; set; }
    public DateTimeOffset At { get; set; } = DateTimeOffset.UtcNow;
    public required string Action { get; set; }
    public required string Subject { get; set; }
    public string Details { get; set; } = "";
    public string Actor { get; set; } = "admin";
}
