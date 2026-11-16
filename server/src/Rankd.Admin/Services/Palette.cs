using System.Globalization;

namespace Rankd.Admin.Services;

/// <summary>Colour helpers shared by thumbnails, topic covers and charts.</summary>
public static class Palette
{
    /// <summary>A gradient from the topic accent, hue-shifted per item so neighbours differ.</summary>
    public static string Gradient(string accent, string seed)
    {
        var (h, s, l) = ToHsl(accent);
        int shift = seed.Aggregate(17, (acc, c) => unchecked(acc * 31 + c)) % 40 - 20;
        return $"linear-gradient(135deg, hsl({(h + shift + 360) % 360:0} {s:0}% {Math.Min(68, l + 6):0}%), hsl({(h + shift + 40) % 360:0} {Math.Min(95, s + 5):0}% {Math.Max(30, l - 12):0}%))";
    }

    public static string Cover(string accent)
    {
        var (h, s, l) = ToHsl(accent);
        return $"linear-gradient(135deg, hsl({h:0} {s:0}% {l:0}%) 0%, hsl({(h + 32) % 360:0} {Math.Min(95, s + 8):0}% {Math.Max(28, l - 16):0}%) 100%)";
    }

    public static (double H, double S, double L) ToHsl(string hex)
    {
        hex = hex.TrimStart('#');
        if (hex.Length < 6) return (258, 100, 68);
        double r = int.Parse(hex[..2], NumberStyles.HexNumber) / 255.0;
        double g = int.Parse(hex[2..4], NumberStyles.HexNumber) / 255.0;
        double b = int.Parse(hex[4..6], NumberStyles.HexNumber) / 255.0;
        double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b));
        double h = 0, s, l = (max + min) / 2;
        if (max == min) s = 0;
        else
        {
            double d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            h = max == r ? (g - b) / d + (g < b ? 6 : 0) : max == g ? (b - r) / d + 2 : (r - g) / d + 4;
            h *= 60;
        }
        return (h, s * 100, l * 100);
    }

    public static string Compact(double n) => n switch
    {
        >= 1_000_000 => (n / 1_000_000).ToString("0.#", CultureInfo.InvariantCulture) + "M",
        >= 10_000 => (n / 1000).ToString("0", CultureInfo.InvariantCulture) + "k",
        >= 1_000 => (n / 1000).ToString("0.#", CultureInfo.InvariantCulture) + "k",
        _ => n.ToString("0", CultureInfo.InvariantCulture),
    };

    public static string Ago(DateTimeOffset at, DateTimeOffset now)
    {
        var d = now - at;
        if (d.TotalMinutes < 1) return "just now";
        if (d.TotalHours < 1) return $"{(int)d.TotalMinutes}m ago";
        if (d.TotalDays < 1) return $"{(int)d.TotalHours}h ago";
        if (d.TotalDays < 30) return $"{(int)d.TotalDays}d ago";
        return at.ToString("d MMM yyyy", CultureInfo.InvariantCulture);
    }
}
