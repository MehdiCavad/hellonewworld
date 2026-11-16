namespace Rankd.Core.Ranking;

/// <summary>One answered comparison. <see cref="Winner"/> is null for a tie.</summary>
public readonly record struct Outcome(string A, string B, string? Winner, double Weight = 1.0);

/// <summary>
/// Bradley–Terry strengths fitted with Hunter's MM iteration. Each item has a
/// strength p, and i beats j with probability p_i / (p_i + p_j). The fit is
/// regularised by a half-win/half-loss against a virtual average opponent so
/// undefeated and winless items still get a finite rating. Ratings are
/// reported on an Elo-like scale: 1500 + 400·log10(p).
/// </summary>
public static class BradleyTerry
{
    public const double BaseRating = 1500;
    public const double RatingScale = 400;
    public const double Prior = 0.5;
    private const int MaxIterations = 400;
    private const double Tolerance = 1e-10;

    /// <summary>Probability that an item rated <paramref name="ratingA"/> beats one rated <paramref name="ratingB"/>.</summary>
    public static double WinProbability(double ratingA, double ratingB) =>
        1 / (1 + Math.Pow(10, (ratingB - ratingA) / RatingScale));

    /// <summary>Fits a rating for every id in <paramref name="ids"/> from <paramref name="outcomes"/>.</summary>
    public static Dictionary<string, double> Fit(IReadOnlyList<string> ids, IEnumerable<Outcome> outcomes)
    {
        int n = ids.Count;
        var index = new Dictionary<string, int>(n);
        for (int i = 0; i < n; i++) index[ids[i]] = i;

        var wins = new double[n];
        // Sparse counts keep the global fit cheap when a topic has hundreds of items.
        var counts = new Dictionary<int, double>[n];
        for (int i = 0; i < n; i++) counts[i] = new Dictionary<int, double>();

        foreach (var o in outcomes)
        {
            if (!index.TryGetValue(o.A, out var a) || !index.TryGetValue(o.B, out var b) || a == b) continue;
            var w = o.Weight;
            counts[a][b] = counts[a].GetValueOrDefault(b) + w;
            counts[b][a] = counts[b].GetValueOrDefault(a) + w;
            if (o.Winner is null) { wins[a] += 0.5 * w; wins[b] += 0.5 * w; }
            else if (o.Winner == o.A) wins[a] += w;
            else if (o.Winner == o.B) wins[b] += w;
        }

        var strength = new double[n];
        Array.Fill(strength, 1.0);

        for (int iter = 0; iter < MaxIterations; iter++)
        {
            double maxDelta = 0;
            for (int i = 0; i < n; i++)
            {
                // MM update: p_i <- W_i / sum_j n_ij / (p_i + p_j), plus the prior's
                // PRIOR wins over 2·PRIOR games against a strength-1 opponent.
                double denominator = 2 * Prior / (strength[i] + 1);
                foreach (var (j, c) in counts[i]) denominator += c / (strength[i] + strength[j]);
                double next = (wins[i] + Prior) / denominator;
                maxDelta = Math.Max(maxDelta, Math.Abs(next - strength[i]) / (strength[i] == 0 ? 1 : strength[i]));
                strength[i] = next;
            }

            // Only ratios are identified: renormalise to a geometric mean of 1.
            double logSum = 0;
            for (int i = 0; i < n; i++) logSum += Math.Log(strength[i]);
            double scale = Math.Exp(logSum / Math.Max(1, n));
            for (int i = 0; i < n; i++) strength[i] /= scale;

            if (maxDelta < Tolerance) break;
        }

        var result = new Dictionary<string, double>(n);
        for (int i = 0; i < n; i++) result[ids[i]] = BaseRating + RatingScale * Math.Log10(strength[i]);
        return result;
    }
}
