using Rankd.Core.Domain;
using Rankd.Infrastructure.Data;

namespace Rankd.Infrastructure.Services;

/// <summary>Records admin actions so curation changes can be traced and reverted.</summary>
public sealed class AuditLogger(RankdDbContext db, TimeProvider clock)
{
    public async Task LogAsync(string action, string subject, string details = "", CancellationToken ct = default)
    {
        db.AuditLog.Add(new AuditEntry { Action = action, Subject = subject, Details = details, At = clock.GetUtcNow() });
        await db.SaveChangesAsync(ct);
    }
}
