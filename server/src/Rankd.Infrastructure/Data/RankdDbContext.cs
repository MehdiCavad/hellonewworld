using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using Rankd.Core.Domain;

namespace Rankd.Infrastructure.Data;

public sealed class RankdDbContext(DbContextOptions<RankdDbContext> options) : DbContext(options)
{
    public DbSet<Topic> Topics => Set<Topic>();
    public DbSet<Item> Items => Set<Item>();
    public DbSet<Asset> Assets => Set<Asset>();
    public DbSet<Level> Levels => Set<Level>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<RankingSessionRecord> Sessions => Set<RankingSessionRecord>();
    public DbSet<Comparison> Comparisons => Set<Comparison>();
    public DbSet<PersonalRanking> PersonalRankings => Set<PersonalRanking>();
    public DbSet<GlobalRanking> GlobalRankings => Set<GlobalRanking>();
    public DbSet<AuditEntry> AuditLog => Set<AuditEntry>();

    protected override void ConfigureConventions(ModelConfigurationBuilder builder)
    {
        // SQLite (the zero-setup dev database) cannot order or compare
        // DateTimeOffset, so store it as a sortable integer there. SQL Server
        // keeps its native datetimeoffset type.
        if (Database.IsSqlite())
            builder.Properties<DateTimeOffset>().HaveConversion<DateTimeOffsetToBinaryConverter>();
    }

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Topic>(e =>
        {
            e.HasIndex(t => t.Slug).IsUnique();
            e.Property(t => t.Slug).HasMaxLength(64);
            e.Property(t => t.Name).HasMaxLength(120);
            e.Property(t => t.Emoji).HasMaxLength(16);
            e.Property(t => t.Description).HasMaxLength(400);
            e.Property(t => t.MediaKind).HasMaxLength(32);
            e.Property(t => t.Accent).HasMaxLength(9);
        });

        b.Entity<Item>(e =>
        {
            e.HasIndex(i => new { i.TopicId, i.Tier });
            e.Property(i => i.Name).HasMaxLength(200);
            e.Property(i => i.Detail).HasMaxLength(120);
            e.Property(i => i.WikiTitle).HasMaxLength(200);
            e.Property(i => i.TmdbId).HasMaxLength(32);
            e.Property(i => i.MusicBrainzId).HasMaxLength(64);
            e.Property(i => i.WikidataId).HasMaxLength(32);
            e.HasOne(i => i.Topic).WithMany(t => t.Items).HasForeignKey(i => i.TopicId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Asset>(e =>
        {
            e.HasIndex(a => new { a.ItemId, a.IsEnabled });
            e.Property(a => a.Url).HasMaxLength(1000);
            e.Property(a => a.SourceUrl).HasMaxLength(1000);
            e.Property(a => a.Provider).HasMaxLength(40);
            e.Property(a => a.ProviderId).HasMaxLength(200);
            e.Property(a => a.Licence).HasMaxLength(120);
            e.Property(a => a.Attribution).HasMaxLength(400);
            e.Property(a => a.DisabledReason).HasMaxLength(400);
            e.HasOne(a => a.Item).WithMany(i => i.Assets).HasForeignKey(a => a.ItemId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Level>(e =>
        {
            e.Property(l => l.Id).HasMaxLength(32);
            e.Property(l => l.Name).HasMaxLength(60);
            e.Property(l => l.Tiers).HasMaxLength(20);
            e.Ignore(l => l.TierList);
        });

        b.Entity<Device>(e =>
        {
            e.Property(d => d.Platform).HasMaxLength(20);
            e.Property(d => d.AppVersion).HasMaxLength(20);
            e.HasIndex(d => d.LastSeenAt);
        });

        b.Entity<RankingSessionRecord>(e =>
        {
            e.ToTable("Sessions");
            e.Property(s => s.LevelId).HasMaxLength(32);
            e.Property(s => s.Mode).HasMaxLength(16);
            e.HasIndex(s => new { s.DeviceId, s.UpdatedAt });
            e.HasIndex(s => new { s.TopicId, s.Status });
            e.HasOne(s => s.Device).WithMany().HasForeignKey(s => s.DeviceId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(s => s.Topic).WithMany().HasForeignKey(s => s.TopicId).OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<Comparison>(e =>
        {
            e.HasIndex(c => new { c.SessionId, c.ClientSequence }).IsUnique();
            e.HasIndex(c => c.CreatedAt);
            e.HasOne(c => c.Session).WithMany(s => s.Comparisons).HasForeignKey(c => c.SessionId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<PersonalRanking>(e =>
        {
            e.HasKey(p => new { p.SessionId, p.ItemId });
            e.HasOne<RankingSessionRecord>().WithMany(s => s.Rankings).HasForeignKey(p => p.SessionId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<GlobalRanking>(e =>
        {
            e.HasKey(g => new { g.TopicId, g.ItemId });
            e.HasIndex(g => new { g.TopicId, g.Rank });
            e.HasOne(g => g.Item).WithMany().HasForeignKey(g => g.ItemId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne<Topic>().WithMany().HasForeignKey(g => g.TopicId).OnDelete(DeleteBehavior.NoAction);
        });

        b.Entity<AuditEntry>(e =>
        {
            e.ToTable("AuditLog");
            e.Property(a => a.Action).HasMaxLength(60);
            e.Property(a => a.Subject).HasMaxLength(200);
            e.Property(a => a.Details).HasMaxLength(1000);
            e.Property(a => a.Actor).HasMaxLength(60);
            e.HasIndex(a => a.At);
        });
    }
}
