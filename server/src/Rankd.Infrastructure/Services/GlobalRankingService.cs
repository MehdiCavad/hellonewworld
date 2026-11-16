using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Rankd.Core.Domain;
using Rankd.Core.Ranking;
using Rankd.Infrastructure.Data;

namespace Rankd.Infrastructure.Services;

public sealed class GlobalRankingOptions
{
    /// <summary>How often the background job refits every topic.</summary>
    public TimeSpan Interval { get; set; } = TimeSpan.FromMinutes(15);
    /// <summary>Sessions with fewer answers say too little to count.</summary>
    public int MinComparisonsPerSession { get; set; } = 5;
    /// <summary>Sessions answered faster than this on average look automated and are ignored.</summary>
    public TimeSpan MinSecondsPerAnswer { get; set; } = TimeSpan.FromMilliseconds(400);
    /// <summary>A device's total weight in a topic is capped at this many answers, so one device cannot outvote the rest.</summary>
    public int DeviceAnswerCap { get; set; } = 300;
}

public sealed record RecomputeResult(int Topics, int Items, int Comparisons, int Devices, TimeSpan Elapsed);

/// <summary>
/// The community ranking: the same Bradley–Terry model fitted over every
/// device's comparisons per topic, with the anti-abuse rules from scope §11.
/// </summary>
public sealed class GlobalRankingService(RankdDbContext db, TimeProvider clock, IOptions<GlobalRankingOptions> options)
{
    private readonly GlobalRankingOptions _o = options.Value;

    public async Task<RecomputeResult> RecomputeAsync(int? topicId = null, CancellationToken ct = default)
    {
        var started = clock.GetTimestamp();
        var topics = await db.Topics.Where(t => topicId == null || t.Id == topicId).Select(t => t.Id).ToListAsync(ct);
        int items = 0, comparisons = 0;
        var devices = new HashSet<Guid>();

        foreach (var id in topics)
        {
            var r = await RecomputeTopicAsync(id, ct);
            items += r.Items;
            comparisons += r.Comparisons;
            devices.UnionWith(r.Devices);
        }
        return new RecomputeResult(topics.Count, items, comparisons, devices.Count, clock.GetElapsedTime(started));
    }

    private async Task<(int Items, int Comparisons, HashSet<Guid> Devices)> RecomputeTopicAsync(int topicId, CancellationToken ct)
    {
        var itemIds = await db.Items.Where(i => i.TopicId == topicId && i.IsActive).Select(i => i.Id).ToListAsync(ct);

        var rows = await db.Comparisons
            .Where(c => c.Session!.TopicId == topicId && !c.Session.Device!.IsBlocked)
            .Select(c => new { c.SessionId, c.Session!.DeviceId, c.ItemAId, c.ItemBId, c.Outcome, c.CreatedAt })
            .ToListAsync(ct);

        // Drop sessions that are too short or implausibly fast.
        var sessions = rows.GroupBy(r => r.SessionId)
            .Where(g => g.Count() >= _o.MinComparisonsPerSession)
            .Where(g =>
            {
                var span = g.Max(r => r.CreatedAt) - g.Min(r => r.CreatedAt);
                return span.TotalMilliseconds / Math.Max(1, g.Count() - 1) >= _o.MinSecondsPerAnswer.TotalMilliseconds;
            })
            .SelectMany(g => g)
            .ToList();

        // Cap each device's influence.
        var perDevice = sessions.GroupBy(r => r.DeviceId).ToDictionary(g => g.Key, g => g.Count());
        var outcomes = sessions.Select(r => new Outcome(
            r.ItemAId.ToString(), r.ItemBId.ToString(),
            r.Outcome switch
            {
                ComparisonOutcome.A => r.ItemAId.ToString(),
                ComparisonOutcome.B => r.ItemBId.ToString(),
                _ => null,
            },
            Math.Min(1.0, (double)_o.DeviceAnswerCap / perDevice[r.DeviceId]))).ToList();

        var ids = itemIds.Select(i => i.ToString()).ToList();
        var ratings = BradleyTerry.Fit(ids, outcomes);

        var counts = itemIds.ToDictionary(i => i, _ => (N: 0, W: 0, L: 0, T: 0));
        foreach (var r in sessions)
        {
            if (!counts.ContainsKey(r.ItemAId) || !counts.ContainsKey(r.ItemBId)) continue;
            var a = counts[r.ItemAId];
            var b = counts[r.ItemBId];
            a.N++; b.N++;
            switch (r.Outcome)
            {
                case ComparisonOutcome.Tie: a.T++; b.T++; break;
                case ComparisonOutcome.A: a.W++; b.L++; break;
                default: b.W++; a.L++; break;
            }
            counts[r.ItemAId] = a;
            counts[r.ItemBId] = b;
        }

        var previous = await db.GlobalRankings.AsNoTracking().Where(g => g.TopicId == topicId)
            .Select(g => new { g.ItemId, g.Rank }).ToDictionaryAsync(g => g.ItemId, g => g.Rank, ct);
        await db.GlobalRankings.Where(g => g.TopicId == topicId).ExecuteDeleteAsync(ct);

        var now = clock.GetUtcNow();
        int rank = 0;
        foreach (var id in itemIds.OrderByDescending(i => ratings[i.ToString()]).ThenByDescending(i => counts[i].W))
        {
            var c = counts[id];
            db.GlobalRankings.Add(new GlobalRanking
            {
                TopicId = topicId, ItemId = id, Rank = ++rank, Rating = ratings[id.ToString()],
                ComparisonCount = c.N, Wins = c.W, Losses = c.L, Ties = c.T,
                PreviousRank = previous.TryGetValue(id, out var p) ? p : null, ComputedAt = now,
            });
        }
        await db.SaveChangesAsync(ct);
        return (itemIds.Count, sessions.Count, perDevice.Keys.ToHashSet());
    }
}

/// <summary>Recomputes community rankings on a timer, off the request path.</summary>
public sealed class GlobalRankingWorker(IServiceScopeFactory scopes, IOptions<GlobalRankingOptions> options, ILogger<GlobalRankingWorker> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(options.Value.Interval);
        do
        {
            try
            {
                using var scope = scopes.CreateScope();
                var result = await scope.ServiceProvider.GetRequiredService<GlobalRankingService>().RecomputeAsync(ct: stoppingToken);
                log.LogInformation("Global rankings: {Topics} topics, {Comparisons} comparisons from {Devices} devices in {Elapsed}",
                    result.Topics, result.Comparisons, result.Devices, result.Elapsed);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                log.LogError(ex, "Global ranking recompute failed");
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}
