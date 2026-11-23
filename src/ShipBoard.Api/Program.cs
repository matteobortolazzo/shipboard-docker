using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using ShipBoard.Api;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using OpenTelemetry.Exporter;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Npgsql;
using Microsoft.Extensions.DependencyInjection;

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

builder.Services.AddHealthChecks().AddDbContextCheck<ShipBoardDb>();
builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

// Configure the shared OTLP connection used by logs, metrics, and traces.
var otlpEndpoint = new Uri(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]!);
Action<OtlpExporterOptions> configureOtlp = options =>
{
    options.Endpoint = otlpEndpoint;
    options.Protocol = OtlpExportProtocol.Grpc;
    options.Headers = builder.Configuration["OTEL_EXPORTER_OTLP_HEADERS"]; // To secure endpoint (not in this example)
};

// Setup logging to be exported via OpenTelemetry
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.IncludeFormattedMessage = true;
    logging.IncludeScopes = true;
    logging.AddOtlpExporter(configureOtlp);
});

var otel = builder.Services.AddOpenTelemetry();

// Identify this application as a single service in the Aspire dashboard.
otel.ConfigureResource(resource => resource.AddService(builder.Configuration["OTEL_SERVICE_NAME"]!));

// Custom metrics for the application
var greeterMeter = new Meter("OTel.Example", "1.0.0");
var countGreetings = greeterMeter.CreateCounter<int>("greetings.count", description: "Counts the number of greetings");

// Custom ActivitySource for the application
var greeterActivitySource = new ActivitySource("OTel.Example");

// Add Metrics for ASP.NET Core and our custom metrics and export via OTLP
otel.WithMetrics(metrics =>
{
    // Metrics provider from OpenTelemetry
    metrics.AddAspNetCoreInstrumentation();

    // Our custom metrics
    metrics.AddMeter(greeterMeter.Name);

    // Metrics provided by ASP.NET Core in .NET
    metrics.AddMeter("Microsoft.AspNetCore.Hosting");
    metrics.AddMeter("Microsoft.AspNetCore.Server.Kestrel");

    // Export the metrics via OTLP
    metrics.AddOtlpExporter(configureOtlp);
});

// Add Tracing for ASP.NET Core and our custom ActivitySource and export via OTLP
otel.WithTracing(tracing =>
{
    tracing.AddAspNetCoreInstrumentation();
    tracing.AddHttpClientInstrumentation();
    tracing.AddNpgsql();
    tracing.AddSource(greeterActivitySource.Name);
    tracing.AddOtlpExporter(configureOtlp);
});


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
