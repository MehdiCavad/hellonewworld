using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Rankd.Infrastructure.Data;

/// <summary>
/// Used by `dotnet ef` only. Migrations target SQL Server, the production
/// database; the SQLite development database is created directly from the model.
/// </summary>
public sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<RankdDbContext>
{
    public RankdDbContext CreateDbContext(string[] args)
    {
        var connection = Environment.GetEnvironmentVariable("RANKD_SQLSERVER")
                         ?? "Server=localhost;Database=Rankd;Trusted_Connection=True;TrustServerCertificate=True";
        return new RankdDbContext(new DbContextOptionsBuilder<RankdDbContext>().UseSqlServer(connection).Options);
    }
}
