using System.Net;

namespace Rankd.Admin.Services;

/// <summary>
/// The admin panel has no sign-in in this phase (scope §5.4 and §7), so it is
/// only served to the internal network: requests from addresses outside the
/// configured CIDR ranges get a 404, as if the panel were not there.
/// </summary>
public sealed class AdminNetworkGuard(RequestDelegate next, IConfiguration config, ILogger<AdminNetworkGuard> log)
{
    private readonly IReadOnlyList<IPNetwork> _allowed =
        (config.GetSection("Admin:AllowedNetworks").Get<string[]>() ?? ["127.0.0.0/8", "::1/128"])
        .Select(IPNetwork.Parse).ToList();

    public async Task InvokeAsync(HttpContext http)
    {
        var remote = http.Connection.RemoteIpAddress;
        if (remote is null || remote.Equals(IPAddress.IPv6Loopback) || IsAllowed(remote))
        {
            await next(http);
            return;
        }
        log.LogWarning("Refused admin request from {Address}", remote);
        http.Response.StatusCode = StatusCodes.Status404NotFound;
    }

    private bool IsAllowed(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        return _allowed.Any(n => n.Contains(address));
    }
}
