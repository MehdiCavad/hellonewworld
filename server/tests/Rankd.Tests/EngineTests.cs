using Rankd.Core.Catalogue;
using Rankd.Core.Ranking;
using Rankd.Infrastructure.Services;

namespace Rankd.Tests;

/// <summary>The web prototype's engine suite (tests/engine.test.js), ported as acceptance tests for the C# engine.</summary>
public class EngineTests
{
    private static RankingSession NewSession(int n, PairingMode mode = PairingMode.Smart, int target = 30, uint seed = 42) =>
        RankingEngine.Create(Enumerable.Range(0, n).Select(i => ($"i{i}", $"Item {i}", "")), mode, seed, target);

    private static string Other(RankingSession s, string id) => s.Current![0] == id ? s.Current[1] : s.Current[0];

    [Fact]
    public void New_session_opens_with_a_valid_distinct_pair()
    {
        var s = NewSession(8);
        Assert.NotNull(s.Current);
        Assert.NotEqual(s.Current![0], s.Current[1]);
        Assert.Contains(s.Current[0], s.Order);
    }

    [Fact]
    public void Create_rejects_pools_smaller_than_two() => Assert.Throws<ArgumentException>(() => NewSession(1));

    [Fact]
    public void Winner_climbs_and_loser_drops_symmetrically()
    {
        var s = NewSession(8);
        var (a, b) = (s.Current![0], s.Current[1]);
        RankingEngine.Submit(s, a);
        var gain = s.Items[a].Rating - BradleyTerry.BaseRating;
        var loss = BradleyTerry.BaseRating - s.Items[b].Rating;
        Assert.True(gain > 0);
        Assert.Equal(gain, loss, 6);
        Assert.Equal(1, s.Items[a].Wins);
        Assert.Equal(1, s.Items[b].Losses);
        foreach (var id in s.Order.Where(id => id != a && id != b))
            Assert.Equal(BradleyTerry.BaseRating, s.Items[id].Rating, 6);
    }

    [Fact]
    public void Rating_differences_predict_outcomes()
    {
        var s = NewSession(4, target: 99);
        var (a, b) = (s.Current![0], s.Current[1]);
        for (int i = 0; i < 5; i++)
        {
            s.Current = [a, b];
            RankingEngine.Submit(s, a);
        }
        var p = BradleyTerry.WinProbability(s.Items[a].Rating, s.Items[b].Rating);
        Assert.True(p > 0.8, $"five straight wins should imply a strong favourite, got {p:F2}");
        Assert.Equal(1, p + BradleyTerry.WinProbability(s.Items[b].Rating, s.Items[a].Rating), 9);
    }

    [Fact]
    public void A_tie_leaves_equal_ratings_untouched_and_counts_for_both()
    {
        var s = NewSession(8);
        var (a, b) = (s.Current![0], s.Current[1]);
        RankingEngine.Submit(s, null);
        Assert.Equal(BradleyTerry.BaseRating, s.Items[a].Rating, 6);
        Assert.Equal(BradleyTerry.BaseRating, s.Items[b].Rating, 6);
        Assert.Equal(1, s.Items[a].Ties);
        Assert.Equal(1, s.Items[b].Ties);
    }

    [Fact]
    public void Submit_rejects_a_winner_that_is_not_on_screen() =>
        Assert.Throws<ArgumentException>(() => RankingEngine.Submit(NewSession(8), "not-in-pool"));

    [Fact]
    public void Undo_restores_ratings_counters_and_the_pair_exactly()
    {
        var s = NewSession(8);
        RankingEngine.Submit(s, s.Current![1]);
        RankingEngine.Submit(s, null);
        var before = Snapshot(s);
        var pair = s.Current!.ToArray();
        RankingEngine.Submit(s, pair[0]);
        RankingEngine.Undo(s);
        Assert.Equal(before, Snapshot(s));
        Assert.Equal(2, s.History.Count);
        Assert.Equal(pair, s.Current);
    }

    [Fact]
    public void Undo_on_empty_history_is_a_no_op()
    {
        var s = NewSession(8);
        RankingEngine.Undo(s);
        Assert.Empty(s.History);
        Assert.NotNull(s.Current);
    }

    [Fact]
    public void Session_finishes_exactly_at_the_target()
    {
        var s = NewSession(6, target: 10);
        for (int i = 0; i < 10; i++)
        {
            Assert.NotNull(s.Current);
            RankingEngine.Submit(s, s.Current![0]);
        }
        Assert.True(s.Finished);
        Assert.Null(s.Current);
        Assert.Equal(10, s.History.Count);
    }

    [Fact]
    public void Extend_reopens_a_finished_session()
    {
        var s = NewSession(6, target: 4);
        for (int i = 0; i < 4; i++) RankingEngine.Submit(s, s.Current![0]);
        RankingEngine.Extend(s, 5);
        Assert.False(s.Finished);
        Assert.NotNull(s.Current);
        Assert.Equal(9, s.TargetRounds);
    }

    [Fact]
    public void Smart_pairing_covers_every_item_before_repeating_anyone()
    {
        var s = NewSession(12, target: 100);
        for (int i = 0; i < 6; i++) RankingEngine.Submit(s, s.Current![0]);
        Assert.All(s.Order, id => Assert.Equal(1, s.Items[id].Played));
    }

    [Fact]
    public void King_of_the_hill_freezes_the_champion_on_its_side()
    {
        var s = NewSession(10, PairingMode.Gauntlet, 30);
        var champion = s.Current![0];
        RankingEngine.Submit(s, champion);
        for (int i = 0; i < 12; i++)
        {
            Assert.Equal(champion, s.Current![0]);
            Assert.NotEqual(champion, s.Current[1]);
            RankingEngine.Submit(s, champion);
        }
        var challenger = s.Current![1];
        RankingEngine.Submit(s, challenger);
        Assert.Equal(challenger, s.Current![1]);
    }

    [Fact]
    public void Undo_restores_the_exact_left_right_layout()
    {
        var s = NewSession(10, PairingMode.Gauntlet, 30);
        RankingEngine.Submit(s, s.Current![0]);
        var pair = s.Current!.ToArray();
        RankingEngine.Submit(s, s.Current[1]);
        RankingEngine.Undo(s);
        Assert.Equal(pair, s.Current);
    }

    [Fact]
    public void Smart_duels_vary_which_side_an_item_appears_on()
    {
        var s = NewSession(12, target: 80);
        var sides = new Dictionary<string, HashSet<int>>();
        for (int i = 0; i < 60 && s.Current is not null; i++)
        {
            for (int k = 0; k < 2; k++) (sides.TryGetValue(s.Current[k], out var set) ? set : sides[s.Current[k]] = []).Add(k);
            RankingEngine.Submit(s, s.Current[0]);
        }
        Assert.True(sides.Count(kv => kv.Value.Count == 2) >= 8);
    }

    [Fact]
    public void Skip_swaps_the_pair_without_recording_a_result()
    {
        var s = NewSession(10);
        var first = string.Join('|', s.Current!);
        RankingEngine.Skip(s);
        Assert.Empty(s.History);
        Assert.NotEqual(first, string.Join('|', s.Current!));
    }

    [Theory]
    [InlineData(8)]
    [InlineData(16)]
    [InlineData(24)]
    public void Smart_duels_never_show_an_option_in_consecutive_rounds(int n)
    {
        var s = NewSession(n, target: RankingEngine.MaxUsefulRounds(n), seed: (uint)n * 11);
        string[]? prev = null;
        while (s.Current is { } cur)
        {
            if (prev is not null) Assert.Empty(prev.Intersect(cur));
            prev = cur.ToArray();
            RankingEngine.Submit(s, cur[0]);
        }
    }

    [Theory]
    [InlineData(8)]
    [InlineData(16)]
    public void No_pair_is_asked_twice_while_unasked_pairs_remain(int n)
    {
        var s = NewSession(n, target: RankingEngine.MaxUsefulRounds(n), seed: (uint)n * 13);
        var seen = new HashSet<string>();
        while (s.Current is { } cur)
        {
            Assert.True(seen.Add(RankingEngine.PairKey(cur[0], cur[1])));
            RankingEngine.Submit(s, cur[1]);
        }
    }

    [Fact]
    public void King_of_the_hill_benches_the_beaten_side_for_a_round()
    {
        var s = NewSession(12, PairingMode.Gauntlet, 40, 5);
        var rng = RankingEngine.MakeRng(9);
        string[]? prev = null;
        while (s.Current is { } cur)
        {
            if (prev is not null)
            {
                var loser = prev[0] == s.Champion ? prev[1] : prev[0];
                Assert.DoesNotContain(loser, cur);
            }
            prev = cur.ToArray();
            RankingEngine.Submit(s, rng() < 0.7 ? s.Champion ?? cur[0] : cur[0] == s.Champion ? cur[1] : cur[0]);
        }
    }

    [Fact]
    public void A_tiny_pool_still_gets_a_pair_when_repeats_are_unavoidable()
    {
        var s = NewSession(3, target: 9);
        for (int i = 0; i < 9; i++)
        {
            Assert.NotNull(s.Current);
            RankingEngine.Submit(s, s.Current![0]);
        }
        Assert.True(s.Finished);
    }

    [Fact]
    public void Progress_reports_rounds_target_and_coverage()
    {
        var s = NewSession(8, target: 20);
        for (int i = 0; i < 8; i++) RankingEngine.Submit(s, s.Current![0]);
        var p = RankingEngine.GetProgress(s);
        Assert.Equal(8, p.Rounds);
        Assert.Equal(20, p.Target);
        Assert.Equal(12, p.Remaining);
        Assert.InRange(p.Ratio, 0.39, 0.41);
        Assert.True(p.LeastSeen >= 1);
    }

    // Convergence: hidden true strengths, a (noisy) oracle answers, compare orders.
    private static (IReadOnlyList<Standing> Ranked, double Error) Simulate(int n, int rounds, PairingMode mode, uint seed, double noise)
    {
        var s = NewSession(n, mode, rounds, seed);
        var rng = RankingEngine.MakeRng(seed + 1);
        int Truth(string id) => int.Parse(id[1..]);
        while (!s.Finished && s.Current is { } cur)
        {
            var better = Truth(cur[0]) > Truth(cur[1]) ? cur[0] : cur[1];
            RankingEngine.Submit(s, rng() < noise ? Other(s, better) : better);
        }
        var ranked = RankingEngine.Standings(s);
        double error = ranked.Select((row, i) => Math.Abs(n - Truth(row.Id) - (i + 1))).Sum();
        return (ranked, error / n);
    }

    [Fact]
    public void A_clean_oracle_recovers_the_exact_order_at_the_default_depth()
    {
        var (ranked, error) = Simulate(16, RankingEngine.MaxUsefulRounds(16), PairingMode.Smart, 7, 0);
        Assert.Equal(0, error);
        Assert.Equal("i15", ranked[0].Id);
        Assert.Equal("i0", ranked[15].Id);
    }

    [Fact]
    public void Smart_pairing_stays_accurate_with_ten_percent_contradictions()
    {
        var avg = Enumerable.Range(1, 8).Average(seed => Simulate(16, RankingEngine.MaxUsefulRounds(16), PairingMode.Smart, (uint)seed, 0.1).Error);
        Assert.True(avg < 1.2, $"mean rank error should stay under 1.2, got {avg:F2}");
    }

    [Fact]
    public void Smart_pairing_beats_gauntlet_at_the_same_budget()
    {
        var smart = Enumerable.Range(1, 8).Sum(seed => Simulate(16, 34, PairingMode.Smart, (uint)seed, 0.05).Error);
        var gauntlet = Enumerable.Range(1, 8).Sum(seed => Simulate(16, 34, PairingMode.Gauntlet, (uint)seed, 0.05).Error);
        Assert.True(smart < gauntlet, $"smart {smart / 8:F2} should beat gauntlet {gauntlet / 8:F2}");
    }

    [Fact]
    public void Standings_are_sorted_and_expose_confidence()
    {
        var (rows, _) = Simulate(10, 40, PairingMode.Smart, 3, 0);
        for (int i = 1; i < rows.Count; i++)
        {
            Assert.True(rows[i - 1].Rating >= rows[i].Rating);
            Assert.Equal(i + 1, rows[i].Rank);
            Assert.InRange(rows[i].Confidence, double.Epsilon, 1);
        }
    }

    [Fact]
    public void Every_seeded_topic_has_enough_items_for_every_level()
    {
        var catalogue = CatalogueSeeder.Load();
        Assert.Equal(9, catalogue.Topics.Count);
        foreach (var topic in catalogue.Topics)
        foreach (var level in catalogue.Levels)
        {
            var pool = Pools.Build(topic.Items, i => i.Tier, level.Tiers, level.PoolSize, RankingEngine.MakeRng(5));
            Assert.True(pool.Count >= 2);
            Assert.All(pool, i => Assert.Contains(i.Tier, level.Tiers));
            Assert.Equal(pool.Count, pool.Distinct().Count());
            if (level.PoolSize > 0) Assert.True(pool.Count <= level.PoolSize);
            else Assert.Equal(topic.Items.Count, pool.Count);
        }
    }

    [Fact]
    public void Casual_level_only_serves_tier_one_items()
    {
        var movies = CatalogueSeeder.Load().Topics.Single(t => t.Slug == "movies");
        var pool = Pools.Build(movies.Items, i => i.Tier, [1], 8, RankingEngine.MakeRng(9));
        Assert.Equal(8, pool.Count);
        Assert.All(pool, i => Assert.Equal(1, i.Tier));
    }

    [Fact]
    public void Marathon_sizes_its_own_round_count() =>
        Assert.Equal(RankingEngine.MaxUsefulRounds(36), Pools.RoundsFor(0, 36));

    [Fact]
    public void Global_fit_weights_down_a_single_loud_voter()
    {
        // 50 heavily weighted votes for B are capped to the weight of one device.
        var outcomes = Enumerable.Range(0, 10).Select(_ => new Outcome("a", "b", "a"))
            .Concat(Enumerable.Range(0, 50).Select(_ => new Outcome("a", "b", "b", 0.1)));
        var r = BradleyTerry.Fit(["a", "b"], outcomes);
        Assert.True(r["a"] > r["b"]);
    }

    private static string Snapshot(RankingSession s) =>
        string.Join(';', s.Order.Select(id => s.Items[id]).Select(i => $"{i.Id}:{i.Rating:R}:{i.Played}:{i.Wins}:{i.Losses}:{i.Ties}"));
}
