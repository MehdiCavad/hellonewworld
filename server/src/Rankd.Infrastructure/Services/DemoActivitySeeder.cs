using Microsoft.EntityFrameworkCore;
using Rankd.Core.Catalogue;
using Rankd.Core.Domain;
using Rankd.Core.Ranking;
using Rankd.Infrastructure.Data;

namespace Rankd.Infrastructure.Services;

/// <summary>
/// Development-only: simulates a month of anonymous players so the admin
/// dashboards and the app's community rankings have realistic data. Every
/// simulated player has a shared "true" taste plus personal noise and answers
/// through the real ranking engine.
/// </summary>
public sealed class DemoActivitySeeder(RankdDbContext db, GlobalRankingService global, TimeProvider clock)
{
    public async Task<int> SeedAsync(CancellationToken ct = default)
    {
        if (await db.Sessions.AnyAsync(ct)) return 0;

        var rng = RankingEngine.MakeRng(20261116);
        var now = clock.GetUtcNow();
        var topics = await db.Topics.Include(t => t.Items).OrderBy(t => t.SortOrder).ToListAsync(ct);
        var levels = await db.Levels.OrderBy(l => l.SortOrder).ToListAsync(ct);

        // A shared "true" appeal per item: famous items lean stronger, with spread.
        var appeal = topics.SelectMany(t => t.Items).ToDictionary(i => i.Id, i => (4 - i.Tier) * 0.6 + Gaussian(rng) * 0.9);
        // Topic popularity, so the dashboard's bars are not flat.
        var popularity = topics.Select((t, i) => 1.0 / (1 + i * 0.22)).ToArray();

        int sessionCount = 0;
        const int devicesTotal = 260;
        for (int d = 0; d < devicesTotal; d++)
        {
            // Adoption grows over the month: later days get more new devices.
            var firstSeen = now.AddDays(-30 * Math.Pow(rng(), 0.7)).AddMinutes(-rng() * 600);
            var device = new Device
            {
                Id = Guid.NewGuid(), FirstSeenAt = firstSeen, LastSeenAt = firstSeen,
                Platform = rng() < 0.56 ? "android" : "ios", AppVersion = rng() < 0.8 ? "2.0.0" : "1.9.2",
            };
            db.Devices.Add(device);

            int sessionsForDevice = 1 + (int)(rng() * rng() * 6);
            var at = firstSeen;
            for (int s = 0; s < sessionsForDevice && at < now; s++)
            {
                var topic = topics[Pick(popularity, rng)];
                var level = levels[Pick([0.34, 0.4, 0.18, 0.08], rng)];
                var pool = Pools.Build(topic.Items, i => i.Tier, level.TierList, level.PoolSize, rng);
                if (pool.Count < 2) continue;
                int target = Pools.RoundsFor(level.RoundBudget, pool.Count);
                var mode = rng() < 0.78 ? PairingMode.Smart : PairingMode.Gauntlet;
                var engine = RankingEngine.Create(pool.Select(i => (i.Id.ToString(), i.Name, i.Detail)), mode, (uint)(rng() * uint.MaxValue), target);

                // Some players leave early.
                double stopAt = rng() < 0.27 ? 0.2 + rng() * 0.6 : 1.0;
                var taste = pool.ToDictionary(i => i.Id.ToString(), i => appeal[i.Id] + Gaussian(rng) * 0.55);
                var record = new RankingSessionRecord
                {
                    Id = Guid.NewGuid(), DeviceId = device.Id, TopicId = topic.Id, LevelId = level.Id,
                    Mode = mode == PairingMode.Smart ? "smart" : "gauntlet", Seed = engine.Seed, TargetRounds = target,
                    PoolItemIds = string.Join(',', pool.Select(i => i.Id)), CreatedAt = at,
                };

                var t = at;
                while (engine.Current is { } pair && engine.History.Count < target * stopAt)
                {
                    t = t.AddMilliseconds(1300 + rng() * 3200);
                    double diff = taste[pair[0]] - taste[pair[1]];
                    string? winner = Math.Abs(diff) < 0.08 && rng() < 0.5 ? null
                        : rng() < 1 / (1 + Math.Exp(-diff * 2.2)) ? pair[0] : pair[1];
                    record.Comparisons.Add(new Comparison
                    {
                        ClientSequence = engine.History.Count, ItemAId = int.Parse(pair[0]), ItemBId = int.Parse(pair[1]),
                        Outcome = winner is null ? ComparisonOutcome.Tie : winner == pair[0] ? ComparisonOutcome.A : ComparisonOutcome.B,
                        CreatedAt = t,
                    });
                    RankingEngine.Submit(engine, winner, t);
                }

                record.Status = engine.Finished ? SessionStatus.Finished
                    : now - t > TimeSpan.FromDays(3) ? SessionStatus.Abandoned : SessionStatus.Active;
                record.UpdatedAt = t;
                foreach (var row in RankingEngine.Standings(engine))
                    record.Rankings.Add(new PersonalRanking
                    {
                        ItemId = int.Parse(row.Id), Rank = row.Rank, Rating = row.Rating, Wins = row.Wins,
                        Losses = row.Losses, Ties = row.Ties, Confidence = row.Confidence,
                    });
                db.Sessions.Add(record);
                device.LastSeenAt = t;
                sessionCount++;
                at = t.AddHours(2 + rng() * 120);
            }
        }

        // A couple of suspicious devices for the anti-abuse view.
        foreach (var d in db.ChangeTracker.Entries<Device>().Select(e => e.Entity).Take(2)) d.IsBlocked = true;

        db.AuditLog.AddRange(
            new AuditEntry { At = now.AddDays(-12), Action = "topic.create", Subject = "Cities", Details = "Imported from launch catalogue" },
            new AuditEntry { At = now.AddDays(-6), Action = "item.tier", Subject = "Parasite", Details = "Tier 3 → 2" },
            new AuditEntry { At = now.AddDays(-2), Action = "device.block", Subject = "2 devices", Details = "Answers under 400 ms each" });

        await db.SaveChangesAsync(ct);
        await global.RecomputeAsync(ct: ct);
        return sessionCount;
    }

    private static int Pick(IReadOnlyList<double> weights, Func<double> rng)
    {
        double r = rng() * weights.Sum();
        for (int i = 0; i < weights.Count; i++)
            if ((r -= weights[i]) <= 0) return i;
        return weights.Count - 1;
    }

    private static double Gaussian(Func<double> rng) =>
        Math.Sqrt(-2 * Math.Log(Math.Max(1e-12, rng()))) * Math.Cos(2 * Math.PI * rng());
}
