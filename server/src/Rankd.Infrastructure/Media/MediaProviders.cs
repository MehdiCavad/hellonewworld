using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Rankd.Core.Domain;

namespace Rankd.Infrastructure.Media;

/// <summary>A found media reference, before it is stored as an <see cref="Asset"/>.</summary>
public sealed record MediaCandidate(int ItemId, AssetType Type, string Url, string Provider, string? ProviderId,
    string? SourceUrl, string Licence, string Attribution);

public interface IMediaProvider
{
    string Name { get; }
    bool Supports(string mediaKind);
    /// <summary>Minimum pause between requests, to respect the provider's rate limit.</summary>
    TimeSpan Spacing { get; }
    /// <summary>How many items one request can cover.</summary>
    int BatchSize { get; }
    Task<IReadOnlyList<MediaCandidate>> FindAsync(HttpClient http, Topic topic, IReadOnlyList<Item> items, CancellationToken ct);
}

/// <summary>
/// Free photos via Wikipedia's pageimages, restricted to Wikimedia Commons
/// files (which carry free licences); the licence and author are read from
/// the file's own metadata.
/// </summary>
public sealed partial class WikipediaMediaProvider : IMediaProvider
{
    public string Name => "Wikimedia Commons";
    public bool Supports(string mediaKind) => mediaKind == MediaKinds.Wikipedia;
    public TimeSpan Spacing => TimeSpan.FromMilliseconds(250);
    public int BatchSize => 40;

    public async Task<IReadOnlyList<MediaCandidate>> FindAsync(HttpClient http, Topic topic, IReadOnlyList<Item> items, CancellationToken ct)
    {
        var titleOf = items.ToDictionary(i => i.Id, i => i.WikiTitle ?? i.Name);
        var titles = string.Join('|', titleOf.Values.Distinct());
        var url = "https://en.wikipedia.org/w/api.php?action=query&format=json&formatversion=2&redirects=1" +
                  "&prop=pageimages|info&inprop=url&piprop=original|name&titles=" + Uri.EscapeDataString(titles);
        using var doc = JsonDocument.Parse(await http.GetStringAsync(url, ct));
        var query = doc.RootElement.GetProperty("query");

        // Follow normalisation and redirects back to the title we asked for.
        var alias = new Dictionary<string, string>();
        foreach (var key in new[] { "normalized", "redirects" })
            if (query.TryGetProperty(key, out var list))
                foreach (var m in list.EnumerateArray())
                    alias[m.GetProperty("to").GetString()!] = m.GetProperty("from").GetString()!;

        string Resolve(string title)
        {
            var seen = 0;
            while (alias.TryGetValue(title, out var from) && seen++ < 4) title = from;
            return title;
        }

        var results = new List<MediaCandidate>();
        foreach (var page in query.GetProperty("pages").EnumerateArray())
        {
            if (!page.TryGetProperty("original", out var original)) continue;
            var src = original.GetProperty("source").GetString()!;
            if (!src.Contains("/wikipedia/commons/")) continue; // fair-use uploads live under /wikipedia/en/
            var requested = Resolve(page.GetProperty("title").GetString()!);
            var file = page.TryGetProperty("pageimage", out var pi) ? pi.GetString() : null;
            var (licence, artist) = file is null ? ("", "") : await ReadLicenceAsync(http, file, ct);

            foreach (var item in items.Where(i => titleOf[i.Id] == requested))
                results.Add(new MediaCandidate(item.Id, AssetType.Image, Thumb(src, 800), Name, file,
                    page.TryGetProperty("fullurl", out var full) ? full.GetString() : null,
                    string.IsNullOrEmpty(licence) ? "See Commons file page" : licence,
                    string.IsNullOrEmpty(artist) ? "Wikimedia Commons" : $"{artist} / Wikimedia Commons"));
        }
        return results;
    }

    private static async Task<(string Licence, string Artist)> ReadLicenceAsync(HttpClient http, string file, CancellationToken ct)
    {
        var url = "https://commons.wikimedia.org/w/api.php?action=query&format=json&formatversion=2&prop=imageinfo" +
                  "&iiprop=extmetadata&titles=" + Uri.EscapeDataString("File:" + file);
        try
        {
            using var doc = JsonDocument.Parse(await http.GetStringAsync(url, ct));
            var meta = doc.RootElement.GetProperty("query").GetProperty("pages")[0].GetProperty("imageinfo")[0].GetProperty("extmetadata");
            string Read(string key) => meta.TryGetProperty(key, out var v) ? StripTags(v.GetProperty("value").GetString() ?? "") : "";
            return (Read("LicenseShortName"), Read("Artist"));
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or KeyNotFoundException or IndexOutOfRangeException)
        {
            return ("", "");
        }
    }

    /// <summary>Commons serves resized copies at /thumb/…/{width}px-{name}.</summary>
    private static string Thumb(string original, int width)
    {
        var marker = "/wikipedia/commons/";
        var i = original.IndexOf(marker, StringComparison.Ordinal);
        if (i < 0 || original.EndsWith(".svg", StringComparison.OrdinalIgnoreCase)) return original;
        var path = original[(i + marker.Length)..];
        var name = path[(path.LastIndexOf('/') + 1)..];
        return $"{original[..(i + marker.Length)]}thumb/{path}/{width}px-{name}";
    }

    private static string StripTags(string html) => TagRegex().Replace(html, "").Trim();

    [GeneratedRegex("<[^>]+>")]
    private static partial Regex TagRegex();
}

/// <summary>Posters, season art, album covers and 30-second previews from the iTunes Search API.</summary>
public sealed class ItunesMediaProvider : IMediaProvider
{
    public string Name => "Apple iTunes";
    public bool Supports(string mediaKind) => mediaKind.StartsWith("itunes:", StringComparison.Ordinal);
    // About 20 requests a minute before Apple starts refusing.
    public TimeSpan Spacing => TimeSpan.FromSeconds(3.1);
    public int BatchSize => 1;

    public async Task<IReadOnlyList<MediaCandidate>> FindAsync(HttpClient http, Topic topic, IReadOnlyList<Item> items, CancellationToken ct)
    {
        var entity = topic.MediaKind["itunes:".Length..];
        var results = new List<MediaCandidate>();
        foreach (var item in items)
        {
            var term = entity == "song" ? $"{item.Name} {item.Detail}" : item.Name;
            var url = $"https://itunes.apple.com/search?limit=5&entity={entity}&term={Uri.EscapeDataString(term)}";
            var response = await http.GetFromJsonAsync<ItunesResponse>(url, ct);
            var hit = response?.Results?.FirstOrDefault(r => YearMatches(r, item, entity)) ?? response?.Results?.FirstOrDefault();
            if (hit?.ArtworkUrl100 is null) continue;

            var store = hit.TrackViewUrl ?? hit.CollectionViewUrl;
            var id = (hit.TrackId ?? hit.CollectionId)?.ToString();
            results.Add(new MediaCandidate(item.Id, AssetType.Image, hit.ArtworkUrl100.Replace("100x100bb", "600x600bb"),
                Name, id, store, "Apple promotional artwork", "Courtesy of Apple"));
            if (entity == "song" && hit.PreviewUrl is not null)
                results.Add(new MediaCandidate(item.Id, AssetType.Audio, hit.PreviewUrl, Name, id, store,
                    "Apple 30-second preview", "Preview courtesy of Apple Music"));
        }
        return results;
    }

    private static bool YearMatches(ItunesResult r, Item item, string entity) =>
        entity != "movie" || r.ReleaseDate is null || item.Detail.Length != 4 || r.ReleaseDate.StartsWith(item.Detail, StringComparison.Ordinal);

    private sealed record ItunesResponse(List<ItunesResult>? Results);

    private sealed record ItunesResult(long? TrackId, long? CollectionId, string? ArtworkUrl100, string? PreviewUrl,
        string? TrackViewUrl, string? CollectionViewUrl, string? ReleaseDate);
}
