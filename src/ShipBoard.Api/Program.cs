using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using ShipBoard.Api;

var builder = WebApplication.CreateBuilder(args);

// Con una connection string usa PostgreSQL, altrimenti un database in memoria.
// Cosi' l'app parte con un semplice `dotnet run`, anche senza Docker.
var connectionString = builder.Configuration.GetConnectionString("shipboard");
builder.Services.AddDbContext<ShipBoardDb>(options =>
{
    if (string.IsNullOrWhiteSpace(connectionString))
        options.UseInMemoryDatabase("shipboard");
    else
        options.UseNpgsql(connectionString);
});

// OpenTelemetry: log, tracce e metriche. Il nome del servizio arriva da OTEL_SERVICE_NAME.
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.IncludeFormattedMessage = true;
    logging.IncludeScopes = true;
});
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddSource(Telemetry.Name)
        .AddSource("Npgsql") // le query SQL verso PostgreSQL
        .AddAspNetCoreInstrumentation(o => o.Filter = ctx => ctx.Request.Path != "/health")
        .AddHttpClientInstrumentation())
    .WithMetrics(metrics => metrics
        .AddMeter(Telemetry.Name)
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation());

// Esporta in OTLP solo se qualcuno ci dice dove (OTEL_EXPORTER_OTLP_ENDPOINT): in locale la dashboard di Aspire.
if (!string.IsNullOrWhiteSpace(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]))
    builder.Services.AddOpenTelemetry().UseOtlpExporter();

builder.Services.AddHealthChecks().AddDbContextCheck<ShipBoardDb>();
builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

var app = builder.Build();

// Crea lo schema all'avvio: comodo a lezione, in produzione si usano le migration.
using (var scope = app.Services.CreateScope())
{
    await scope.ServiceProvider.GetRequiredService<ShipBoardDb>().Database.EnsureCreatedAsync();
}

app.MapGet("/", () => Results.Redirect("/info"));

// Utile per vedere "dove" gira l'app: dentro un container l'hostname e' l'id del container.
app.MapGet("/info", (IConfiguration config) => new
{
    app = "ShipBoard.Api",
    version = config["APP_VERSION"] ?? "dev",
    host = Environment.MachineName,
    user = Environment.UserName,
    os = System.Runtime.InteropServices.RuntimeInformation.OSDescription,
    database = string.IsNullOrWhiteSpace(connectionString) ? "in-memory" : "postgresql"
});

app.MapHealthChecks("/health");
app.MapTickets();

app.Run();

public partial class Program;
