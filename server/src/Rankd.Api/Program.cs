using System.Net;
using System.Threading.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Rankd.Api.Endpoints;
using Rankd.Infrastructure;
using Rankd.Infrastructure.Data;
using Rankd.Infrastructure.Services;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(o => o.IncludeScopes = true);

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddRankdInfrastructure(builder.Configuration);
builder.Services.Configure<GlobalRankingOptions>(builder.Configuration.GetSection("GlobalRanking"));
if (builder.Configuration.GetValue("GlobalRanking:Enabled", true))
    builder.Services.AddHostedService<GlobalRankingWorker>();

builder.Services.AddOpenApi(o => o.AddDocumentTransformer((doc, _, _) =>
{
    doc.Info.Title = "Rankd API";
    doc.Info.Version = "v1";
    doc.Info.Description = "Public API for the Rankd app. Anonymous: device-scoped calls carry a random GUID in the X-Rankd-Device header.";
    return Task.CompletedTask;
}));
builder.Services.AddOutputCache(o => o.AddPolicy("catalogue", p => p.Expire(TimeSpan.FromSeconds(30)).SetVaryByQuery("take")));
// The mobile app does not need CORS; this is for the Flutter web build used in development.
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
{
    if (builder.Environment.IsDevelopment()) p.AllowAnyOrigin();
    else p.WithOrigins(builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? []);
    p.AllowAnyHeader().AllowAnyMethod().WithExposedHeaders("ETag");
}));

// No authentication in this phase (scope §5.4), so abuse control is rate
// limiting partitioned by device id, falling back to the client address.
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    static string Partition(HttpContext http) =>
        http.Request.Headers.TryGetValue(DeviceEndpoints.DeviceHeader, out var d) && Guid.TryParse(d, out _)
            ? "d:" + d
            : "ip:" + (http.Connection.RemoteIpAddress ?? IPAddress.None);

    o.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(http =>
        RateLimitPartition.GetFixedWindowLimiter(Partition(http), _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = builder.Configuration.GetValue("RateLimits:RequestsPerMinute", 240),
            Window = TimeSpan.FromMinutes(1),
        }));
    o.AddPolicy("writes", http => RateLimitPartition.GetSlidingWindowLimiter(Partition(http), _ => new SlidingWindowRateLimiterOptions
    {
        PermitLimit = builder.Configuration.GetValue("RateLimits:WritesPerMinute", 60),
        Window = TimeSpan.FromMinutes(1),
        SegmentsPerWindow = 6,
    }));
});
builder.Services.Configure<Microsoft.AspNetCore.Server.Kestrel.Core.KestrelServerOptions>(k => k.Limits.MaxRequestBodySize = 1_000_000);

var app = builder.Build();

await app.Services.InitialiseRankdDatabaseAsync();

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
    app.UseHttpsRedirection();
}
app.UseCors();
app.UseRateLimiter();
app.UseOutputCache();

app.MapOpenApi();
if (app.Environment.IsDevelopment())
    app.MapScalarApiReference("/docs", o => o.WithTitle("Rankd API"));

app.MapGet("/", () => Results.Redirect(app.Environment.IsDevelopment() ? "/docs" : "/healthz")).ExcludeFromDescription();
app.MapGet("/healthz", async (RankdDbContext db, CancellationToken ct) =>
        await db.Database.CanConnectAsync(ct) ? Results.Ok(new { status = "ok" }) : Results.StatusCode(503))
    .ExcludeFromDescription();

var v1 = app.MapGroup("/api/v1").WithTags("Rankd");
v1.MapCatalogue();
v1.MapRankings();
v1.MapDeviceScoped();

app.Run();

/// <summary>Exposed for WebApplicationFactory in the integration tests.</summary>
public partial class Program;
