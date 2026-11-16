namespace Rankd.Infrastructure.Contracts;

// Public API shapes shared by the API, its tests and the Flutter client.

public sealed record LevelDto(string Id, string Name, string Emoji, string Description, IReadOnlyList<int> Tiers, int PoolSize, int RoundBudget);

public sealed record TopicSummaryDto(
    string Slug, string Name, string Emoji, string Description, string MediaKind, string Accent,
    int ItemCount, IReadOnlyDictionary<int, int> ItemsPerTier, string? CoverImageUrl, DateTimeOffset UpdatedAt);

public sealed record MediaDto(string Type, string Url, string Provider, string? SourceUrl, string Licence, string Attribution);

public sealed record ItemDto(int Id, string Name, string Detail, int Tier, MediaDto? Image, MediaDto? Audio);

public sealed record TopicDetailDto(
    string Slug, string Name, string Emoji, string Description, string MediaKind, string Accent,
    DateTimeOffset UpdatedAt, IReadOnlyList<ItemDto> Items);

public sealed record ComparisonUpload(int Seq, int A, int B, string Outcome, DateTimeOffset At);

/// <summary>
/// A whole session as the device currently has it. Uploading is idempotent:
/// the comparison list replaces what the server holds, keyed by sequence, so a
/// retried or out-of-order upload converges and an undo on the device simply
/// shortens the list.
/// </summary>
public sealed record SessionUpload(
    string TopicSlug, string LevelId, string Mode, long Seed, int TargetRounds, string Status,
    IReadOnlyList<int> PoolItemIds, IReadOnlyList<ComparisonUpload> Comparisons, DateTimeOffset CreatedAt);

public sealed record SessionSyncResult(Guid Id, int Comparisons, string Status, DateTimeOffset UpdatedAt);

public sealed record SessionSummaryDto(Guid Id, string TopicSlug, string LevelId, string Mode, string Status, int Comparisons, int TargetRounds, DateTimeOffset UpdatedAt);

public sealed record GlobalRankingRowDto(int Rank, int? PreviousRank, int ItemId, string Name, string Detail, double Rating, int Comparisons, int Wins, int Losses, int Ties, MediaDto? Image);

public sealed record GlobalRankingDto(string TopicSlug, DateTimeOffset? ComputedAt, int Devices, IReadOnlyList<GlobalRankingRowDto> Rows);

public sealed record ProviderAttributionDto(string Provider, string Notice, string Url, int Assets);

public sealed record ApiProblem(string Title, string Detail);
