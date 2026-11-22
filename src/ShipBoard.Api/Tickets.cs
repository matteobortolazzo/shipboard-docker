using Microsoft.EntityFrameworkCore;

namespace ShipBoard.Api;

public enum Priority { Low, Medium, High }

public class Ticket
{
    public int Id { get; set; }
    public required string Title { get; set; }
    public Priority Priority { get; set; } = Priority.Medium;
    public bool Done { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public record CreateTicket(string Title, Priority Priority = Priority.Medium);

public class ShipBoardDb(DbContextOptions<ShipBoardDb> options) : DbContext(options)
{
    public DbSet<Ticket> Tickets => Set<Ticket>();
}

public static class TicketEndpoints
{
    public static void MapTickets(this WebApplication app)
    {
        var tickets = app.MapGroup("/tickets");

        tickets.MapGet("/", async (ShipBoardDb db, IConfiguration config, Priority? priority) =>
        {
            // Span personalizzato: nella dashboard compare dentro lo span di GET /tickets.
            using var activity = Telemetry.Source.StartActivity("carica-ticket");
            activity?.SetTag("shipboard.filtro.priorita", priority?.ToString() ?? "tutte");

            // DELAY_MS simula una dipendenza lenta: provate a trovarla nelle tracce.
            if (config.GetValue<int>("DELAY_MS") is > 0 and var delay)
                await Task.Delay(delay);

            var list = await db.Tickets
                .Where(t => priority == null || t.Priority == priority)
                .OrderByDescending(t => t.CreatedAt)
                .ToListAsync();
            activity?.SetTag("shipboard.ticket.count", list.Count);
            return list;
        });

        tickets.MapGet("/{id:int}", async (int id, ShipBoardDb db) =>
            await db.Tickets.FindAsync(id) is { } t ? Results.Ok(t) : Results.NotFound());

        tickets.MapPost("/", async (CreateTicket input, ShipBoardDb db, ILoggerFactory loggers) =>
        {
            if (string.IsNullOrWhiteSpace(input.Title))
                return Results.ValidationProblem(new Dictionary<string, string[]>
                {
                    ["title"] = ["Il titolo è obbligatorio."]
                });

            var ticket = new Ticket { Title = input.Title.Trim(), Priority = input.Priority };
            db.Tickets.Add(ticket);
            await db.SaveChangesAsync();

            Telemetry.TicketsCreated.Add(1, new KeyValuePair<string, object?>("priority", ticket.Priority.ToString()));
            // Log strutturato: Id e Priority diventano campi filtrabili, collegati alla traccia della richiesta.
            loggers.CreateLogger("ShipBoard.Tickets")
                .LogInformation("Creato il ticket {TicketId} con priorita' {Priority}", ticket.Id, ticket.Priority);
            return Results.Created($"/tickets/{ticket.Id}", ticket);
        });

        tickets.MapPost("/{id:int}/done", async (int id, ShipBoardDb db) =>
        {
            var ticket = await db.Tickets.FindAsync(id);
            if (ticket is null) return Results.NotFound();
            ticket.Done = true;
            await db.SaveChangesAsync();
            return Results.Ok(ticket);
        });
    }
}
