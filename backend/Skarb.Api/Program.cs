using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Endpoints;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Common.Security;
using Skarb.Api.Common.Services;
using Skarb.Api.Features.Import;
using Skarb.Api.Features.Notifications;
using Skarb.Api.Features.Sync;
using Skarb.Api.Infrastructure.Banking.EnableBanking;
using Skarb.Api.Infrastructure.Banking.Monobank;
using Skarb.Api.Infrastructure.Fx;
using Skarb.Api.Infrastructure.Notifications;

var builder = WebApplication.CreateBuilder(args);

// --- persistence ---
builder.Services.AddDbContext<SkarbDbContext>(o =>
    o.UseNpgsql(builder.Configuration.GetConnectionString("Default")
        ?? "Host=localhost;Port=5432;Database=skarb;Username=skarb;Password=skarb"));

// --- options ---
builder.Services.Configure<SyncOptions>(builder.Configuration.GetSection(SyncOptions.Section));
builder.Services.Configure<FxOptions>(builder.Configuration.GetSection(FxOptions.Section));

// --- security (owner sign-in, session cookie, deny-by-default authorization) ---
builder.Services.AddSkarbAuthentication(builder.Configuration, builder.Environment);
builder.Services.AddSkarbRateLimiting();

// --- core pipeline (SRP: ingest → categorize → detect transfers) ---
builder.Services.AddHttpClient();
builder.Services.AddScoped<ITransactionIngestor, TransactionIngestor>();
builder.Services.AddScoped<ICategorizer, RuleBasedCategorizer>();
builder.Services.AddScoped<ITransferDetector, TransferDetector>();
builder.Services.AddSingleton<IExchangeRateService, OpenErApiExchangeRateService>();

// --- bank providers (add a new bank = add one IBankProvider registration) ---
builder.Services.AddScoped<MonobankApiClient>();
builder.Services.AddScoped<EnableBankingApiClient>();
builder.Services.AddScoped<EnableBankingProvider>();
builder.Services.AddScoped<IBankProvider, MonobankProvider>();
builder.Services.AddScoped<IBankProvider>(sp => sp.GetRequiredService<EnableBankingProvider>());

// --- features ---
builder.Services.AddScoped<CsvImportService>();
builder.Services.AddSingleton<TelegramApiClient>();
builder.Services.AddSingleton<ILowBalanceAlerter, LowBalanceAlerter>();
builder.Services.AddSingleton<ISyncService, SyncService>();
builder.Services.AddHostedService<BackgroundSyncService>();

var authOptions = builder.Configuration.GetSection(AuthOptions.Section).Get<AuthOptions>() ?? new AuthOptions();
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    // Credentialed requests forbid a wildcard origin, so the list stays explicit.
    .WithOrigins(["http://localhost:5173", "http://127.0.0.1:5173", .. authOptions.AllowedOrigins])
    .AllowCredentials()
    .AllowAnyHeader()
    .AllowAnyMethod()));

builder.Services.AddOpenApi();

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<SkarbDbContext>();
    await db.Database.MigrateAsync();
    await Seed.EnsureSeededAsync(db);
    await SetupAnnouncement.WriteIfUnclaimedAsync(scope.ServiceProvider, app.Logger);
}

// Behind a reverse proxy (Caddy, nginx, Cloudflare) the app only learns the request was
// HTTPS from these headers — without them "Secure" cookies never get set.
// Only a loopback proxy is trusted out of the box. A containerised proxy (Caddy on a
// shared Docker network) connects from its bridge address instead, so the networks it
// may speak for are configurable: ForwardedHeaders__KnownNetworks__0=172.16.0.0/12.
var forwardedHeaders = new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
};
foreach (var network in app.Configuration.GetSection("ForwardedHeaders:KnownNetworks").Get<string[]>() ?? [])
    forwardedHeaders.KnownIPNetworks.Add(System.Net.IPNetwork.Parse(network));
app.UseForwardedHeaders(forwardedHeaders);

// Bank/provider failures are expected operational errors (bad redirect URI, expired
// consent, rate limit) — surface their message to the UI instead of a bare 500.
// Anything else is a bug, and its message stays out of the response once deployed.
app.UseExceptionHandler(errApp => errApp.Run(async ctx =>
{
    var ex = ctx.Features.Get<Microsoft.AspNetCore.Diagnostics.IExceptionHandlerFeature>()?.Error;
    var expected = ex is InvalidOperationException;
    ctx.Response.StatusCode = expected ? StatusCodes.Status400BadRequest : StatusCodes.Status500InternalServerError;
    var message = expected || app.Environment.IsDevelopment()
        ? ex?.Message ?? "Unexpected error"
        : "Unexpected error";
    await ctx.Response.WriteAsJsonAsync(new { error = message });
}));

var hasFrontend = Directory.Exists(Path.Combine(app.Environment.ContentRootPath, "wwwroot"));

// Static assets are served ahead of authorization on purpose. The deny-by-default policy
// also covers requests that match no endpoint, and /assets/*.js is exactly that — leaving
// it behind the gate would 401 the bundle and leave nobody able to reach the sign-in form.
// The bundle carries no data of its own; the API behind it is what's protected.
if (hasFrontend)
{
    app.UseDefaultFiles();
    app.UseStaticFiles();
}

app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

if (app.Environment.IsDevelopment()) app.MapOpenApi();

app.MapEndpointGroups();

// Deep links (/settings, /accounts) fall back to the SPA shell, which then decides
// whether to show the sign-in screen or the app.
if (hasFrontend) app.MapFallbackToFile("index.html").AllowAnonymous();

app.Run();
