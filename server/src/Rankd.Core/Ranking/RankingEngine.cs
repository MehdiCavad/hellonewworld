namespace Rankd.Core.Ranking;

public enum PairingMode
{
    /// <summary>Serve the pair the ranking is least sure about.</summary>
    Smart,
    /// <summary>King of the hill: the winner stays on and defends.</summary>
    Gauntlet,
}

public sealed class EngineItem
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public string Detail { get; init; } = "";
    public double Rating { get; set; } = BradleyTerry.BaseRating;
    public int Played { get; set; }
    public int Wins { get; set; }
    public int Losses { get; set; }
    public int Ties { get; set; }
}

public sealed record Round(string A, string B, string? Winner, string? PreviousChampion, DateTimeOffset At);

/// <summary>
/// A ranking session. The comparison history is the only source of truth:
/// ratings are re-derived from it, which keeps undo exact and makes a session
/// safe to store and resume anywhere.
/// </summary>
public sealed class RankingSession
{
    public Dictionary<string, EngineItem> Items { get; } = new();
    public List<string> Order { get; } = new();
    public List<Round> History { get; } = new();
    public Dictionary<string, int> PairSeen { get; } = new();
    public PairingMode Mode { get; init; }
    public uint Seed { get; init; }
    public int TargetRounds { get; set; }
    public int Skips { get; set; }
    public string? Champion { get; set; }
    public string[]? Current { get; set; }
    public bool Finished { get; set; }
}

public sealed record Standing(
    int Rank, string Id, string Name, string Detail, double Rating, int Played,
    int Wins, int Losses, int Ties, double WinRate, double Confidence);

public sealed record Progress(int Rounds, int Target, int Remaining, double Ratio, double Coverage, int LeastSeen);

/// <summary>
/// C# port of the prototype's engine.js: Bradley–Terry ratings with adaptive
/// pairing. Behaviour, constants and the PRNG match the prototype, so its
/// test suite doubles as the acceptance suite for this port.
/// </summary>
public static class RankingEngine
{
    private const double Never = 100_000;      // a cost no rating gap can outweigh
    private const double OverSamplePenalty = 70;
    private const double ShortlistWindow = 40;

    public static Func<double> MakeRng(uint seed)
    {
        uint t = seed == 0 ? 1u : seed;
        return () =>
        {
            unchecked
            {
                t += 0x6D2B79F5;
                uint r = t;
                r = (r ^ (r >> 15)) * (r | 1);
                r ^= r + (r ^ (r >> 7)) * (r | 61);
                return (r ^ (r >> 14)) / 4294967296.0;
            }
        };
    }

    public static string PairKey(string a, string b) => string.CompareOrdinal(a, b) < 0 ? $"{a}|{b}" : $"{b}|{a}";

    public static int MaxUsefulRounds(int n) => n < 2 ? 0 : Math.Max(n, (int)Math.Round(n * Math.Log2(n) * 0.9, MidpointRounding.AwayFromZero));

    public static RankingSession Create(IEnumerable<(string Id, string Name, string Detail)> pool, PairingMode mode, uint seed, int targetRounds)
    {
        var session = new RankingSession { Mode = mode, Seed = seed, TargetRounds = targetRounds };
        foreach (var (id, name, detail) in pool)
        {
            if (session.Items.ContainsKey(id)) continue;
            session.Items[id] = new EngineItem { Id = id, Name = name, Detail = detail };
            session.Order.Add(id);
        }
        if (session.Order.Count < 2) throw new ArgumentException("A session needs at least 2 items", nameof(pool));
        session.Current = NextPair(session);
        return session;
    }

    public static void Refit(RankingSession session)
    {
        var ratings = BradleyTerry.Fit(session.Order, session.History.Select(r => new Outcome(r.A, r.B, r.Winner)));
        foreach (var (id, rating) in ratings) session.Items[id].Rating = rating;
    }

    /// <summary>Re-seeded from the round number so a restored session replays the same stream.</summary>
    private static Func<double> RngFor(RankingSession s) =>
        MakeRng(unchecked((uint)(s.Seed + (long)s.History.Count * 7919 + (long)s.Skips * 104729)));

    public static string[]? NextPair(RankingSession session)
    {
        var ids = session.Order;
        if (ids.Count < 2) return null;
        var random = RngFor(session);
        var items = session.Items;
        int minPlayed = ids.Min(id => items[id].Played);

        var champion = session.Mode == PairingMode.Gauntlet && session.Champion is { } c && items.ContainsKey(c) ? c : null;

        // Options shown last round, other than a reigning champion, sit out the next one.
        var bench = new HashSet<string>((session.Current ?? []).Where(id => id != champion));

        var pairs = new List<(string A, string B, double Cost)>();
        for (int i = 0; i < ids.Count; i++)
        for (int j = i + 1; j < ids.Count; j++)
        {
            var a = items[ids[i]];
            var b = items[ids[j]];
            if (champion is not null && a.Id != champion && b.Id != champion) continue;
            int seen = session.PairSeen.GetValueOrDefault(PairKey(a.Id, b.Id));
            double cost = Math.Abs(a.Rating - b.Rating)
                          + seen * Never
                          + ((bench.Contains(a.Id) ? 1 : 0) + (bench.Contains(b.Id) ? 1 : 0)) * Never
                          + (a.Played - minPlayed) * OverSamplePenalty
                          + (b.Played - minPlayed) * OverSamplePenalty;
            pairs.Add((a.Id, b.Id, cost));
        }
        if (pairs.Count == 0) return null;

        // Stable sort, like Array.prototype.sort, so ties keep their scan order.
        var sorted = pairs.Select((p, i) => (p, i)).OrderBy(x => x.p.Cost).ThenBy(x => x.i).Select(x => x.p).ToList();
        double best = sorted[0].Cost;
        var shortlist = sorted.Where(p => p.Cost <= best + ShortlistWindow).Take(3).ToList();
        var chosen = shortlist[(int)Math.Floor(random() * shortlist.Count)];

        if (champion is not null)
        {
            // The champion holds the slot it already occupies; only the challenger swaps in.
            var challenger = chosen.A == champion ? chosen.B : chosen.A;
            int held = session.Current is { } cur ? Array.IndexOf(cur, champion) : -1;
            return held == 1 ? [challenger, champion] : [champion, challenger];
        }

        // Randomise sides so screen position never becomes part of the ranking.
        return random() < 0.5 ? [chosen.A, chosen.B] : [chosen.B, chosen.A];
    }

    /// <summary>Records one comparison; <paramref name="winnerId"/> null means "too close to call".</summary>
    public static void Submit(RankingSession s, string? winnerId, DateTimeOffset? at = null)
    {
        if (s.Current is not { } pair) return;
        string a = pair[0], b = pair[1];
        if (winnerId is not null && winnerId != a && winnerId != b)
            throw new ArgumentException("Winner must be one of the two shown items", nameof(winnerId));

        s.History.Add(new Round(a, b, winnerId, s.Champion, at ?? DateTimeOffset.UtcNow));
        Tally(s.Items[a], s.Items[b], winnerId, a, +1);
        var key = PairKey(a, b);
        s.PairSeen[key] = s.PairSeen.GetValueOrDefault(key) + 1;
        s.Champion = winnerId ?? s.Champion;
        Refit(s);

        if (s.TargetRounds > 0 && s.History.Count >= s.TargetRounds)
        {
            s.Finished = true;
            s.Current = null;
        }
        else s.Current = NextPair(s);
    }

    public static void Skip(RankingSession s)
    {
        if (s.Current is not { } pair) return;
        var key = PairKey(pair[0], pair[1]);
        s.PairSeen[key] = s.PairSeen.GetValueOrDefault(key) + 1;
        s.Skips++;
        s.Current = NextPair(s);
    }

    public static void Undo(RankingSession s)
    {
        if (s.History.Count == 0) return;
        var last = s.History[^1];
        s.History.RemoveAt(s.History.Count - 1);
        Tally(s.Items[last.A], s.Items[last.B], last.Winner, last.A, -1);
        var key = PairKey(last.A, last.B);
        s.PairSeen[key] = Math.Max(0, s.PairSeen.GetValueOrDefault(key, 1) - 1);
        s.Champion = last.PreviousChampion;
        s.Finished = false;
        s.Current = [last.A, last.B];
        Refit(s);
    }

    public static void Extend(RankingSession s, int extraRounds = 10)
    {
        s.TargetRounds = s.History.Count + Math.Max(1, extraRounds);
        s.Finished = false;
        s.Current = NextPair(s);
    }

    public static IReadOnlyList<Standing> Standings(RankingSession s) =>
        s.Order.Select(id => s.Items[id])
            .OrderByDescending(i => i.Rating)
            .ThenByDescending(i => i.Wins)
            .ThenBy(i => i.Name, StringComparer.CurrentCulture)
            .Select((i, index) =>
            {
                int decided = i.Wins + i.Losses;
                return new Standing(index + 1, i.Id, i.Name, i.Detail, i.Rating, i.Played, i.Wins, i.Losses, i.Ties,
                    decided == 0 ? 0 : (double)i.Wins / decided,
                    // It takes a handful of comparisons before a position means anything.
                    Math.Min(1, i.Played / 6.0));
            })
            .ToList();

    public static Progress GetProgress(RankingSession s)
    {
        int rounds = s.History.Count;
        int target = s.TargetRounds > 0 ? s.TargetRounds : MaxUsefulRounds(s.Order.Count);
        int minPlayed = s.Order.Count == 0 ? 0 : s.Order.Min(id => s.Items[id].Played);
        return new Progress(rounds, target, Math.Max(0, target - rounds),
            target == 0 ? 1 : Math.Min(1, (double)rounds / target),
            Math.Min(1, minPlayed / 3.0), minPlayed);
    }

    private static void Tally(EngineItem a, EngineItem b, string? winner, string aId, int sign)
    {
        a.Played += sign;
        b.Played += sign;
        if (winner is null) { a.Ties += sign; b.Ties += sign; }
        else if (winner == aId) { a.Wins += sign; b.Losses += sign; }
        else { b.Wins += sign; a.Losses += sign; }
    }
}
