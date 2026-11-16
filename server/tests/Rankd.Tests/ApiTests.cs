using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Rankd.Infrastructure.Contracts;
using Rankd.Infrastructure.Services;

namespace Rankd.Tests;

/// <summary>Boots the real API on a throwaway SQLite database.</summary>
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    private readonly string _db = Path.Combine(Path.GetTempPath(), $"rankd-test-{Guid.NewGuid():N}.db");

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:Rankd", $"Data Source={_db}");
        builder.UseSetting("Database:Provider", "Sqlite");
        builder.UseSetting("Database:SeedDemoActivity", "false");
        builder.UseSetting("GlobalRanking:Enabled", "false");
        builder.UseSetting("RateLimits:WritesPerMinute", "1000");
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        try { File.Delete(_db); } catch (IOException) { }
    }
}

public class ApiTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    private HttpClient Client(Guid? device = null)
    {
        var http = factory.CreateClient();
        if (device is { } d) http.DefaultRequestHeaders.Add("X-Rankd-Device", d.ToString());
        return http;
    }

    private async Task<TopicDetailDto> Topic(string slug) =>
        (await Client().GetFromJsonAsync<TopicDetailDto>($"/api/v1/topics/{slug}"))!;

    private static SessionUpload Upload(TopicDetailDto topic, params (int A, int B, string Outcome)[] answers) => new(
        topic.Slug, "casual", "smart", 7, 14, "active",
        topic.Items.Take(8).Select(i => i.Id).ToList(),
        answers.Select((a, i) => new ComparisonUpload(i, a.A, a.B, a.Outcome, DateTimeOffset.UtcNow.AddSeconds(i * 3))).ToList(),
        DateTimeOffset.UtcNow);

    [Fact]
    public async Task Catalogue_lists_the_nine_launch_topics_and_four_levels()
    {
        var topics = await Client().GetFromJsonAsync<List<TopicSummaryDto>>("/api/v1/topics");
        Assert.Equal(9, topics!.Count);
        Assert.Contains(topics, t => t.Slug == "songs" && t.MediaKind == "itunes:song");
        Assert.All(topics, t => Assert.Equal(t.ItemCount, t.ItemsPerTier.Values.Sum()));

        var levels = await Client().GetFromJsonAsync<List<LevelDto>>("/api/v1/levels");
        Assert.Equal(["casual", "standard", "expert", "marathon"], levels!.Select(l => l.Id));
    }

    [Fact]
    public async Task Topic_detail_supports_conditional_requests()
    {
        var http = Client();
        var first = await http.GetAsync("/api/v1/topics/movies");
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        var etag = first.Headers.ETag;
        Assert.NotNull(etag);

        var again = new HttpRequestMessage(HttpMethod.Get, "/api/v1/topics/movies");
        again.Headers.IfNoneMatch.Add(etag!);
        Assert.Equal(HttpStatusCode.NotModified, (await http.SendAsync(again)).StatusCode);
    }

    [Fact]
    public async Task Unknown_topic_is_404() =>
        Assert.Equal(HttpStatusCode.NotFound, (await Client().GetAsync("/api/v1/topics/nope")).StatusCode);

    [Fact]
    public async Task Device_scoped_calls_require_a_device_id() =>
        Assert.Equal(HttpStatusCode.BadRequest, (await Client().GetAsync("/api/v1/sessions")).StatusCode);

    [Fact]
    public async Task Session_upload_is_idempotent_and_follows_undo()
    {
        var topic = await Topic("food");
        var ids = topic.Items.Take(8).Select(i => i.Id).ToArray();
        var device = Guid.NewGuid();
        var http = Client(device);
        var sessionId = Guid.NewGuid();

        var three = Upload(topic, (ids[0], ids[1], "a"), (ids[2], ids[3], "b"), (ids[4], ids[5], "tie"));
        Assert.Equal(3, (await (await http.PutAsJsonAsync($"/api/v1/sessions/{sessionId}", three)).Content.ReadFromJsonAsync<SessionSyncResult>())!.Comparisons);
        // Retrying the same upload changes nothing.
        Assert.Equal(3, (await (await http.PutAsJsonAsync($"/api/v1/sessions/{sessionId}", three)).Content.ReadFromJsonAsync<SessionSyncResult>())!.Comparisons);

        // The device undid the last answer.
        var two = three with { Comparisons = three.Comparisons.Take(2).ToList() };
        var result = await (await http.PutAsJsonAsync($"/api/v1/sessions/{sessionId}", two)).Content.ReadFromJsonAsync<SessionSyncResult>();
        Assert.Equal(2, result!.Comparisons);

        var mine = await http.GetFromJsonAsync<List<SessionSummaryDto>>("/api/v1/sessions");
        Assert.Single(mine!);
        Assert.Equal(2, mine![0].Comparisons);
    }

    [Fact]
    public async Task Racing_uploads_of_one_session_all_succeed()
    {
        // The app can fire a milestone upload while the previous one is still in flight.
        var topic = await Topic("movies");
        var ids = topic.Items.Take(6).Select(i => i.Id).ToArray();
        var http = Client(Guid.NewGuid());
        var sessionId = Guid.NewGuid();
        var upload = Upload(topic, (ids[0], ids[1], "a"), (ids[2], ids[3], "b"), (ids[4], ids[5], "a"));

        var responses = await Task.WhenAll(Enumerable.Range(0, 6).Select(_ => http.PutAsJsonAsync($"/api/v1/sessions/{sessionId}", upload)));
        Assert.All(responses, r => Assert.True(r.IsSuccessStatusCode, $"{(int)r.StatusCode}"));
        var mine = await http.GetFromJsonAsync<List<SessionSummaryDto>>("/api/v1/sessions");
        Assert.Equal(3, Assert.Single(mine!).Comparisons);
    }

    [Fact]
    public async Task Another_device_cannot_overwrite_a_session()
    {
        var topic = await Topic("cities");
        var ids = topic.Items.Take(8).Select(i => i.Id).ToArray();
        var sessionId = Guid.NewGuid();
        var upload = Upload(topic, (ids[0], ids[1], "a"));
        Assert.True((await Client(Guid.NewGuid()).PutAsJsonAsync($"/api/v1/sessions/{sessionId}", upload)).IsSuccessStatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Client(Guid.NewGuid()).PutAsJsonAsync($"/api/v1/sessions/{sessionId}", upload)).StatusCode);
    }

    [Fact]
    public async Task Invalid_pairs_are_rejected()
    {
        var topic = await Topic("movies");
        var ids = topic.Items.Take(8).Select(i => i.Id).ToArray();
        var other = (await Topic("food")).Items[0].Id;
        var http = Client(Guid.NewGuid());
        Assert.Equal(HttpStatusCode.BadRequest, (await http.PutAsJsonAsync($"/api/v1/sessions/{Guid.NewGuid()}", Upload(topic, (ids[0], ids[0], "a")))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await http.PutAsJsonAsync($"/api/v1/sessions/{Guid.NewGuid()}", Upload(topic, (ids[0], other, "a")))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await http.PutAsJsonAsync($"/api/v1/sessions/{Guid.NewGuid()}", Upload(topic, (ids[0], ids[1], "left")))).StatusCode);
    }

    [Fact]
    public async Task Deleting_my_data_removes_the_device_and_its_sessions()
    {
        var topic = await Topic("series");
        var ids = topic.Items.Take(8).Select(i => i.Id).ToArray();
        var device = Guid.NewGuid();
        var http = Client(device);
        await http.PutAsJsonAsync($"/api/v1/sessions/{Guid.NewGuid()}", Upload(topic, (ids[0], ids[1], "a")));

        Assert.Equal(HttpStatusCode.NoContent, (await http.DeleteAsync("/api/v1/devices/me")).StatusCode);
        Assert.Empty((await http.GetFromJsonAsync<List<SessionSummaryDto>>("/api/v1/sessions"))!);
    }

    [Fact]
    public async Task Global_ranking_pools_every_device()
    {
        var topic = await Topic("languages");
        var ids = topic.Items.Take(8).Select(i => i.Id).ToArray();
        // Three devices all prefer ids[0] over everything; answers are spaced like a human.
        for (int d = 0; d < 3; d++)
        {
            var answers = Enumerable.Range(1, 7).Select(i => (ids[0], ids[i], "a")).ToArray();
            await Client(Guid.NewGuid()).PutAsJsonAsync($"/api/v1/sessions/{Guid.NewGuid()}", Upload(topic, answers));
        }

        using (var scope = factory.Services.CreateScope())
            await scope.ServiceProvider.GetRequiredService<GlobalRankingService>().RecomputeAsync();

        var ranking = await Client().GetFromJsonAsync<GlobalRankingDto>("/api/v1/topics/languages/global-ranking?take=5");
        Assert.Equal(ids[0], ranking!.Rows[0].ItemId);
        Assert.Equal(21, ranking.Rows[0].Wins);
        Assert.Equal(3, ranking.Devices);
    }
}
