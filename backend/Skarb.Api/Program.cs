using Microsoft.EntityFrameworkCore;
using Skarb.Api.Common.Abstractions;
using Skarb.Api.Common.Endpoints;
using Skarb.Api.Common.Persistence;
using Skarb.Api.Common.Services;
using Skarb.Api.Features.Import;
using Skarb.Api.Features.Sync;
using Skarb.Api.Infrastructure.Banking.EnableBanking;
using Skarb.Api.Infrastructure.Banking.Monobank;
using Skarb.Api.Infrastructure.Fx;

var builder = WebApplication.CreateBuilder(args);

// --- persistence ---
builder.Services.AddDbContext<SkarbDbContext>(o =>
    o.UseNpgsql(builder.Configuration.GetConnectionString("Default")
        ?? "Host=localhost;Port=5432;Database=skarb;Username=skarb;Password=skarb"));

// --- options ---
builder.Services.Configure<SyncOptions>(builder.Configuration.GetSection(SyncOptions.Section));

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
builder.Services.AddSingleton<ISyncService, SyncService>();
builder.Services.AddHostedService<BackgroundSyncService>();

builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins("http://localhost:5173", "http://127.0.0.1:5173")
    .AllowAnyHeader()
    .AllowAnyMethod()));

builder.Services.AddOpenApi();

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<SkarbDbContext>();
    await db.Database.MigrateAsync();
    await Seed.EnsureSeededAsync(db);
}

app.UseCors();
app.MapOpenApi();

app.MapEndpointGroups();

// Serve the built frontend when it has been published into wwwroot.
if (Directory.Exists(Path.Combine(app.Environment.ContentRootPath, "wwwroot")))
{
    app.UseDefaultFiles();
    app.UseStaticFiles();
    app.MapFallbackToFile("index.html");
}

app.Run();
