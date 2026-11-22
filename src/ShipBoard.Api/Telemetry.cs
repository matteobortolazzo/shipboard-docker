using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace ShipBoard.Api;

// Telemetria "nostra", oltre a quella automatica di ASP.NET Core e Npgsql.
// Il nome deve coincidere con AddSource/AddMeter in Program.cs, altrimenti nessuno la raccoglie.
public static class Telemetry
{
    public const string Name = "ShipBoard.Api";

    // Traccia: ogni StartActivity crea uno span figlio dello span della richiesta HTTP.
    public static readonly ActivitySource Source = new(Name);

    // Metrica: un contatore che si puo' sommare e filtrare per priorita'.
    private static readonly Meter Meter = new(Name);
    public static readonly Counter<long> TicketsCreated =
        Meter.CreateCounter<long>("shipboard.tickets.created", unit: "{ticket}", description: "Ticket creati");
}
