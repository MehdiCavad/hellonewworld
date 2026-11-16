using Microsoft.EntityFrameworkCore;
using Rankd.Core.Domain;
using Rankd.Infrastructure.Data;

namespace Rankd.Admin.Services;

public sealed record DayPoint(DateOnly Day, int Sessions, int Answers, int NewDevices);

public sealed record TopicActivity(int TopicId, string Slug, string Name, string Emoji, string Accent, int Sessions, int Answers, int Finished, int Items, int ItemsWithImage);

public sealed record DashboardData(
    int Topics, int Items, int ItemsWithImage, int Devices, int ActiveDevices7d, int ActiveDevicesPrev7d,
    int Sessions, int Sessions7d, int SessionsPrev7d, int Answers, int Answers7d, int AnswersPrev7d,
    double CompletionRate, int Android, int Ios, int BlockedDevices,
    IReadOnlyList<DayPoint> Days, IReadOnlyList<TopicActivity> TopicStats,
    IReadOnlyList<(string Level, int Count)> Levels, IReadOnlyList<(string Mode, int Count)> Modes,
    IReadOnlyList<AuditEntry> Recent, DateTimeOffset? RankingsComputedAt);

/// <summary>Read models for the admin pages. Each call uses its own short-lived context.</summary>
public sealed class AdminQueries(IDbContextFactory<RankdDbContext> factory, TimeProvider clock)
{
    public async Task<DashboardData> DashboardAsync(CancellationToken ct = default)
    {
        await using var db = await factory.CreateDbContextAsync(ct);
        var now = clock.GetUtcNow();
        var since = now.AddDays(-30);

        var sessions = await db.Sessions.AsNoTracking()
            .Select(s => new { s.CreatedAt, s.UpdatedAt, s.TopicId, s.LevelId, s.Mode, s.Status, Answers = s.Comparisons.Count })
            .ToListAsync(ct);
        var devices = await db.Devices.AsNoTracking().Select(d => new { d.FirstSeenAt, d.LastSeenAt, d.Platform, d.IsBlocked }).ToListAsync(ct);
        var topics = await db.Topics.AsNoTracking().OrderBy(t => t.SortOrder).ToListAsync(ct);
        var items = await db.Items.AsNoTracking().Where(i => i.IsActive)
            .Select(i => new { i.TopicId, HasImage = i.Assets.Any(a => a.IsEnabled && a.Type == AssetType.Image) })
            .ToListAsync(ct);

        var days = Enumerable.Range(0, 30).Select(i => DateOnly.FromDateTime(since.AddDays(i + 1).UtcDateTime)).ToList();
        var sessionsByDay = sessions.Where(s => s.CreatedAt >= since).GroupBy(s => DateOnly.FromDateTime(s.CreatedAt.UtcDateTime))
            .ToDictionary(g => g.Key, g => (Count: g.Count(), Answers: g.Sum(s => s.Answers)));
        var devicesByDay = devices.Where(d => d.FirstSeenAt >= since).GroupBy(d => DateOnly.FromDateTime(d.FirstSeenAt.UtcDateTime))
            .ToDictionary(g => g.Key, g => g.Count());

        bool In(DateTimeOffset t, int fromDaysAgo, int toDaysAgo) => t > now.AddDays(-fromDaysAgo) && t <= now.AddDays(-toDaysAgo);

        var topicStats = topics.Select(t =>
        {
            var mine = sessions.Where(s => s.TopicId == t.Id).ToList();
            var its = items.Where(i => i.TopicId == t.Id).ToList();
            return new TopicActivity(t.Id, t.Slug, t.Name, t.Emoji, t.Accent, mine.Count, mine.Sum(s => s.Answers),
                mine.Count(s => s.Status == SessionStatus.Finished), its.Count, its.Count(i => i.HasImage));
        }).ToList();

        var recent = await db.AuditLog.AsNoTracking().OrderByDescending(a => a.At).Take(7).ToListAsync(ct);
        var computed = await db.GlobalRankings.AsNoTracking().OrderByDescending(g => g.ComputedAt).Select(g => (DateTimeOffset?)g.ComputedAt).FirstOrDefaultAsync(ct);
        var levelNames = await db.Levels.AsNoTracking().OrderBy(l => l.SortOrder).ToDictionaryAsync(l => l.Id, l => l.Name, ct);

        return new DashboardData(
            topics.Count, items.Count, items.Count(i => i.HasImage), devices.Count,
            devices.Count(d => In(d.LastSeenAt, 7, 0)), devices.Count(d => In(d.LastSeenAt, 14, 7)),
            sessions.Count, sessions.Count(s => In(s.CreatedAt, 7, 0)), sessions.Count(s => In(s.CreatedAt, 14, 7)),
            sessions.Sum(s => s.Answers), sessions.Where(s => In(s.CreatedAt, 7, 0)).Sum(s => s.Answers),
            sessions.Where(s => In(s.CreatedAt, 14, 7)).Sum(s => s.Answers),
            sessions.Count == 0 ? 0 : (double)sessions.Count(s => s.Status == SessionStatus.Finished) / sessions.Count,
            devices.Count(d => d.Platform == "android"), devices.Count(d => d.Platform == "ios"), devices.Count(d => d.IsBlocked),
            days.Select(d => new DayPoint(d,
                sessionsByDay.TryGetValue(d, out var s) ? s.Count : 0,
                sessionsByDay.TryGetValue(d, out var s2) ? s2.Answers : 0,
                devicesByDay.GetValueOrDefault(d))).ToList(),
            topicStats,
            levelNames.Select(l => (l.Value, sessions.Count(s => s.LevelId == l.Key))).ToList(),
            [("Smart duels", sessions.Count(s => s.Mode == "smart")), ("King of the hill", sessions.Count(s => s.Mode == "gauntlet"))],
            recent, computed);
    }
}
