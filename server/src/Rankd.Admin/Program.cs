using Rankd.Admin.Components;
using Rankd.Admin.Services;
using Rankd.Infrastructure;
using Rankd.Infrastructure.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddRankdInfrastructure(builder.Configuration);
builder.Services.Configure<GlobalRankingOptions>(builder.Configuration.GetSection("GlobalRanking"));
builder.Services.AddScoped<AdminQueries>();
builder.Services.AddScoped<Toasts>();

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

var app = builder.Build();

await app.Services.InitialiseRankdDatabaseAsync();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    app.UseHsts();
    app.UseHttpsRedirection();
}

app.UseMiddleware<AdminNetworkGuard>();
app.UseStatusCodePagesWithReExecute("/not-found", createScopeForStatusCodePages: true);
app.UseAntiforgery();

app.MapStaticAssets();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
