using Microsoft.EntityFrameworkCore;
using Rankd.Core.Domain;
using Rankd.Infrastructure.Contracts;
using Rankd.Infrastructure.Data;
using Rankd.Infrastructure.Services;

namespace Rankd.Api.Endpoints;

/// <summary>Endpoints scoped to the calling device. There are no accounts: the device id is the only identity.</summary>
public static class DeviceEndpoints
{
    public const string DeviceHeader = "X-Rankd-Device";

    public static RouteGroupBuilder MapDeviceScoped(this RouteGroupBuilder api)
    {
        var me = api.MapGroup("").AddEndpointFilter(RequireDevice).RequireRateLimiting("writes");

        me.MapPut("/sessions/{id:guid}", async (Guid id, SessionUpload body, HttpContext http, SessionSyncService sync, CancellationToken ct) =>
            {
                var device = DeviceId(http);
                try
                {
                    await sync.TouchDeviceAsync(device, http.Request.Headers["X-Rankd-Platform"], http.Request.Headers["X-Rankd-Version"], ct);
                    return Results.Ok(await sync.SyncAsync(device, id, body, ct));
                }
                catch (SyncException ex)
                {
                    return Results.Json(new ApiProblem("Session rejected", ex.Message), statusCode: ex.StatusCode);
                }
            })
            .WithName("SyncSession")
            .WithSummary("Create or update a session from the device. Idempotent: the uploaded comparison list replaces the stored one.")
            .Produces<SessionSyncResult>().Produces<ApiProblem>(StatusCodes.Status400BadRequest);

        me.MapGet("/sessions", async (HttpContext http, RankdDbContext db, CancellationToken ct) =>
            {
                var device = DeviceId(http);
                return await db.Sessions.AsNoTracking().Where(s => s.DeviceId == device)
                    .OrderByDescending(s => s.UpdatedAt)
                    .Select(s => new SessionSummaryDto(s.Id, s.Topic!.Slug, s.LevelId, s.Mode,
                        s.Status == SessionStatus.Finished ? "finished" : s.Status == SessionStatus.Active ? "active" : "abandoned",
                        s.Comparisons.Count, s.TargetRounds, s.UpdatedAt))
                    .ToListAsync(ct);
            })
            .WithName("ListMySessions").WithSummary("Sessions this device has uploaded.");

        me.MapDelete("/devices/me", async (HttpContext http, SessionSyncService sync, CancellationToken ct) =>
                await sync.DeleteDeviceAsync(DeviceId(http), ct) ? Results.NoContent() : Results.NotFound())
            .WithName("DeleteMyData").WithSummary("Delete everything the server holds for this device (FR-18).");

        return api;
    }

    private static Guid DeviceId(HttpContext http) => (Guid)http.Items[DeviceHeader]!;

    private static async ValueTask<object?> RequireDevice(EndpointFilterInvocationContext ctx, EndpointFilterDelegate next)
    {
        var http = ctx.HttpContext;
        if (!Guid.TryParse(http.Request.Headers[DeviceHeader], out var id) || id == Guid.Empty)
            return Results.Json(new ApiProblem("Device id required", $"Send a random GUID in the {DeviceHeader} header."), statusCode: 400);
        http.Items[DeviceHeader] = id;
        return await next(ctx);
    }
}
