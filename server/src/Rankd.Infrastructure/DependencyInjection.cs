using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Rankd.Infrastructure.Data;
using Rankd.Infrastructure.Media;
using Rankd.Infrastructure.Services;

namespace Rankd.Infrastructure;

public sealed class DatabaseOptions
{
    /// <summary>"SqlServer" (production) or "Sqlite" (zero-setup local development).</summary>
    public string Provider { get; set; } = "SqlServer";
    /// <summary>Apply EF Core migrations on startup. Off in production, where the release checklist applies them.</summary>
    public bool MigrateOnStartup { get; set; }
    /// <summary>Seed the launch catalogue when the database is empty.</summary>
    public bool SeedCatalogue { get; set; } = true;
    /// <summary>Simulate a few weeks of player activity so dashboards have something to show. Development only.</summary>
    public bool SeedDemoActivity { get; set; }
}

public static class DependencyInjection
{
    public static IServiceCollection AddRankdInfrastructure(this IServiceCollection services, IConfiguration config)
    {
        var options = config.GetSection("Database").Get<DatabaseOptions>() ?? new DatabaseOptions();
        services.AddSingleton(options);

        var connection = config.GetConnectionString("Rankd")
                         ?? throw new InvalidOperationException("Connection string 'Rankd' is missing.");

        // The factory also registers a scoped RankdDbContext; Blazor Server pages use
        // the factory directly so each operation gets a short-lived context.
        services.AddDbContextFactory<RankdDbContext>(db =>
        {
            if (options.Provider.Equals("Sqlite", StringComparison.OrdinalIgnoreCase))
                db.UseSqlite(connection);
            else
                db.UseSqlServer(connection, sql => sql.EnableRetryOnFailure(3));
        });

        services.AddMemoryCache();
        services.AddScoped<AuditLogger>();
        services.AddScoped<SessionSyncService>();
        services.AddScoped<GlobalRankingService>();
        services.AddScoped<CatalogueSeeder>();
        services.AddScoped<DemoActivitySeeder>();
        services.AddScoped<MediaIngestionService>();
        services.AddHttpClient(MediaIngestionService.HttpClientName, http =>
        {
            http.Timeout = TimeSpan.FromSeconds(15);
            // MusicBrainz and Wikimedia ask for an identifying User-Agent.
            http.DefaultRequestHeaders.UserAgent.ParseAdd("RankdIngestion/2.0 (+https://github.com/MehdiCavad/hellonewworld)");
        });
        services.AddSingleton<IMediaProvider, WikipediaMediaProvider>();
        services.AddSingleton<IMediaProvider, ItunesMediaProvider>();
        return services;
    }

    /// <summary>Creates or migrates the schema, then seeds. Call once at startup.</summary>
    public static async Task InitialiseRankdDatabaseAsync(this IServiceProvider services, CancellationToken ct = default)
    {
        using var scope = services.CreateScope();
        var sp = scope.ServiceProvider;
        var options = sp.GetRequiredService<DatabaseOptions>();
        var db = sp.GetRequiredService<RankdDbContext>();
        var log = sp.GetRequiredService<ILoggerFactory>().CreateLogger("Rankd.Database");

        if (db.Database.IsSqlite())
            await db.Database.EnsureCreatedAsync(ct);
        else if (options.MigrateOnStartup)
            await db.Database.MigrateAsync(ct);

        if (options.SeedCatalogue)
        {
            var added = await sp.GetRequiredService<CatalogueSeeder>().SeedAsync(ct);
            if (added > 0) log.LogInformation("Seeded {Count} topics from the launch catalogue", added);
        }

        if (options.SeedDemoActivity && sp.GetRequiredService<IHostEnvironment>().IsDevelopment())
        {
            var sessions = await sp.GetRequiredService<DemoActivitySeeder>().SeedAsync(ct);
            if (sessions > 0) log.LogInformation("Simulated {Count} demo sessions", sessions);
        }
    }
}
