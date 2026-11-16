using Microsoft.EntityFrameworkCore;
using Rankd.Core.Domain;
using Rankd.Core.Ranking;
using Rankd.Infrastructure.Contracts;
using Rankd.Infrastructure.Data;

namespace Rankd.Infrastructure.Services;

public sealed class SyncException(string message, int statusCode = 400) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

/// <summary>Accepts offline-first session uploads keyed by device id.</summary>
public sealed class SessionSyncService(RankdDbContext db, TimeProvider clock)
{
    public const int MaxComparisons = 5000;
    public const int MaxPool = 1000;

    public async Task<Device> TouchDeviceAsync(Guid deviceId, string? platform, string? appVersion, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        var device = await db.Devices.FindAsync([deviceId], ct);
        if (device is null)
        {
            device = new Device { Id = deviceId, FirstSeenAt = now };
            db.Devices.Add(device);
        }
        device.LastSeenAt = now;
        if (!string.IsNullOrWhiteSpace(platform)) device.Platform = platform[..Math.Min(20, platform.Length)];
        if (!string.IsNullOrWhiteSpace(appVersion)) device.AppVersion = appVersion[..Math.Min(20, appVersion.Length)];
        return device;
    }

    /// <summary>
    /// Touches the device and stores the upload. Two uploads of the same session can
    /// race (a retry overtaking a slow request); the loser sees a unique-key clash,
    /// so it starts again from a clean change tracker and replays against what won.
    /// </summary>
    public async Task<SessionSyncResult> UploadAsync(Guid deviceId, string? platform, string? appVersion, Guid sessionId, SessionUpload upload, CancellationToken ct = default)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                await TouchDeviceAsync(deviceId, platform, appVersion, ct);
                return await SyncAsync(deviceId, sessionId, upload, ct);
            }
            catch (DbUpdateException) when (attempt < 3)
            {
                db.ChangeTracker.Clear();
                await Task.Delay(TimeSpan.FromMilliseconds(40 * attempt), ct);
            }
            catch (DbUpdateException)
            {
                throw new SyncException("The session was being updated by another request. Try again.", 409);
            }
        }
    }

    public async Task<SessionSyncResult> SyncAsync(Guid deviceId, Guid sessionId, SessionUpload upload, CancellationToken ct = default)
    {
        if (sessionId == Guid.Empty) throw new SyncException("Session id must be a non-empty GUID.");
        if (upload.Comparisons.Count > MaxComparisons) throw new SyncException($"At most {MaxComparisons} comparisons per session.");
        if (upload.PoolItemIds.Count is < 2 or > MaxPool) throw new SyncException("A session pool needs between 2 and 1000 items.");
        if (upload.Mode is not ("smart" or "gauntlet")) throw new SyncException("Mode must be 'smart' or 'gauntlet'.");
        if (!Enum.TryParse<SessionStatus>(upload.Status, ignoreCase: true, out var status)) throw new SyncException("Unknown status.");

        var topic = await db.Topics.AsNoTracking().FirstOrDefaultAsync(t => t.Slug == upload.TopicSlug, ct)
                    ?? throw new SyncException($"Unknown topic '{upload.TopicSlug}'.", 404);
        if (!await db.Levels.AnyAsync(l => l.Id == upload.LevelId, ct)) throw new SyncException($"Unknown level '{upload.LevelId}'.");

        var pool = upload.PoolItemIds.Distinct().ToList();
        var known = await db.Items.Where(i => i.TopicId == topic.Id && pool.Contains(i.Id)).Select(i => i.Id).ToListAsync(ct);
        if (known.Count != pool.Count) throw new SyncException("The pool contains items that are not in this topic.");
        var poolSet = pool.ToHashSet();

        var seqs = new HashSet<int>();
        foreach (var c in upload.Comparisons)
        {
            if (!seqs.Add(c.Seq) || c.Seq < 0) throw new SyncException("Comparison sequences must be unique and non-negative.");
            if (c.A == c.B || !poolSet.Contains(c.A) || !poolSet.Contains(c.B)) throw new SyncException($"Comparison {c.Seq} has an invalid pair.");
            if (ParseOutcome(c.Outcome) is null) throw new SyncException($"Comparison {c.Seq} has an unknown outcome.");
        }

        var device = await TouchDeviceAsync(deviceId, null, null, ct);
        var now = clock.GetUtcNow();

        var session = await db.Sessions.Include(s => s.Comparisons).FirstOrDefaultAsync(s => s.Id == sessionId, ct);
        if (session is null)
        {
            session = new RankingSessionRecord
            {
                Id = sessionId, DeviceId = device.Id, TopicId = topic.Id, LevelId = upload.LevelId,
                CreatedAt = upload.CreatedAt == default ? now : upload.CreatedAt,
            };
            db.Sessions.Add(session);
        }
        else if (session.DeviceId != deviceId)
        {
            // Session ids are random GUIDs; a clash with another device is an attack or a bug.
            throw new SyncException("This session belongs to another device.", 403);
        }
        else if (session.TopicId != topic.Id)
        {
            throw new SyncException("A session cannot change topic.", 409);
        }

        session.LevelId = upload.LevelId;
        session.Mode = upload.Mode;
        session.Seed = upload.Seed;
        session.TargetRounds = Math.Max(0, upload.TargetRounds);
        session.Status = status;
        session.PoolItemIds = string.Join(',', pool);
        session.UpdatedAt = now;

        // Converge on the uploaded history: keep identical rows, rewrite changed
        // ones, drop rows the device has undone.
        var incoming = upload.Comparisons.ToDictionary(c => c.Seq);
        foreach (var existing in session.Comparisons.ToList())
        {
            if (!incoming.TryGetValue(existing.ClientSequence, out var c))
            {
                session.Comparisons.Remove(existing);
                db.Comparisons.Remove(existing);
                continue;
            }
            existing.ItemAId = c.A;
            existing.ItemBId = c.B;
            existing.Outcome = ParseOutcome(c.Outcome)!.Value;
            existing.CreatedAt = c.At;
            incoming.Remove(c.Seq);
        }
        foreach (var c in incoming.Values)
        {
            session.Comparisons.Add(new Comparison
            {
                ClientSequence = c.Seq, ItemAId = c.A, ItemBId = c.B,
                Outcome = ParseOutcome(c.Outcome)!.Value, CreatedAt = c.At,
            });
        }

        await db.SaveChangesAsync(ct);
        await RebuildPersonalRankingAsync(session, pool, ct);
        return new SessionSyncResult(session.Id, session.Comparisons.Count, session.Status.ToString().ToLowerInvariant(), session.UpdatedAt);
    }

    private async Task RebuildPersonalRankingAsync(RankingSessionRecord session, List<int> pool, CancellationToken ct)
    {
        await db.PersonalRankings.Where(p => p.SessionId == session.Id).ExecuteDeleteAsync(ct);

        var ids = pool.Select(i => i.ToString()).ToList();
        var outcomes = session.Comparisons.OrderBy(c => c.ClientSequence).Select(ToOutcome).ToList();
        var ratings = BradleyTerry.Fit(ids, outcomes);

        var tally = pool.ToDictionary(i => i, _ => (W: 0, L: 0, T: 0));
        foreach (var c in session.Comparisons)
        {
            var (a, b) = (tally[c.ItemAId], tally[c.ItemBId]);
            switch (c.Outcome)
            {
                case ComparisonOutcome.Tie: a.T++; b.T++; break;
                case ComparisonOutcome.A: a.W++; b.L++; break;
                default: b.W++; a.L++; break;
            }
            tally[c.ItemAId] = a;
            tally[c.ItemBId] = b;
        }

        int rank = 0;
        foreach (var id in pool.OrderByDescending(i => ratings[i.ToString()]).ThenByDescending(i => tally[i].W))
        {
            var t = tally[id];
            db.PersonalRankings.Add(new PersonalRanking
            {
                SessionId = session.Id, ItemId = id, Rank = ++rank, Rating = ratings[id.ToString()],
                Wins = t.W, Losses = t.L, Ties = t.T, Confidence = Math.Min(1, (t.W + t.L + t.T) / 6.0),
            });
        }
        await db.SaveChangesAsync(ct);
    }

    public static Outcome ToOutcome(Comparison c) => new(
        c.ItemAId.ToString(), c.ItemBId.ToString(),
        c.Outcome switch
        {
            ComparisonOutcome.A => c.ItemAId.ToString(),
            ComparisonOutcome.B => c.ItemBId.ToString(),
            _ => null,
        });

    private static ComparisonOutcome? ParseOutcome(string value) => value.ToLowerInvariant() switch
    {
        "a" => ComparisonOutcome.A,
        "b" => ComparisonOutcome.B,
        "tie" => ComparisonOutcome.Tie,
        _ => null,
    };

    /// <summary>FR-18: forget everything this device has sent us.</summary>
    public async Task<bool> DeleteDeviceAsync(Guid deviceId, CancellationToken ct = default)
    {
        var device = await db.Devices.FindAsync([deviceId], ct);
        if (device is null) return false;
        // Cascades remove sessions, comparisons and personal rankings.
        db.Devices.Remove(device);
        await db.SaveChangesAsync(ct);
        return true;
    }
}
