// =============================================================================
// OrderEndpoints.cs
// Minimal API endpoint definitions
// Security: All auth enforced by APIM — backend trusts enriched headers only
// Headers injected by APIM policy: X-Consumer-Id, X-Tenant-Id, X-Consumer-Scope
// =============================================================================

using Microsoft.ApplicationInsights;
using OrderManagement.Api.Models;
using OrderManagement.Api.Services;

namespace OrderManagement.Api.Endpoints;

public static class OrderEndpoints
{
    public static void MapOrderEndpoints(this WebApplication app)
    {
        var orders = app.MapGroup("/orders")
            .WithTags("Orders");

        // GET /orders — list orders for tenant
        orders.MapGet("/", async (
            HttpContext context,
            IOrderService orderService,
            TelemetryClient telemetry,
            int page = 1,
            int pageSize = 20) =>
        {
            // Extract tenant context from APIM-injected headers
            // APIM strips the raw JWT and injects these headers instead
            var tenantId = context.Request.Headers["X-Tenant-Id"].FirstOrDefault() ?? "default";
            var consumerId = context.Request.Headers["X-Consumer-Id"].FirstOrDefault() ?? "unknown";

            // Track who is querying — full audit trail in App Insights
            telemetry.TrackEvent("OrdersListed", new Dictionary<string, string>
            {
                ["tenantId"] = tenantId,
                ["consumerId"] = consumerId,
                ["page"] = page.ToString()
            });

            var result = await orderService.GetOrdersAsync(tenantId, page, pageSize);
            return Results.Ok(result);
        });

        // GET /orders/{id}
        orders.MapGet("/{id:guid}", async (
            Guid id,
            HttpContext context,
            IOrderService orderService) =>
        {
            var tenantId = context.Request.Headers["X-Tenant-Id"].FirstOrDefault() ?? "default";
            var order = await orderService.GetOrderByIdAsync(id, tenantId);
            return order is null ? Results.NotFound() : Results.Ok(order);
        });

        // POST /orders
        orders.MapPost("/", async (
            CreateOrderRequest request,
            HttpContext context,
            IOrderService orderService,
            TelemetryClient telemetry) =>
        {
            var tenantId = context.Request.Headers["X-Tenant-Id"].FirstOrDefault() ?? "default";
            var consumerId = context.Request.Headers["X-Consumer-Id"].FirstOrDefault() ?? "unknown";

            // Basic input validation — APIM validates content-type and payload size
            if (string.IsNullOrWhiteSpace(request.CustomerId))
                return Results.BadRequest(new { error = "CustomerId is required" });

            if (request.LineItems == null || request.LineItems.Count == 0)
                return Results.BadRequest(new { error = "At least one line item is required" });

            var order = await orderService.CreateOrderAsync(request, tenantId, consumerId);

            telemetry.TrackEvent("OrderCreated", new Dictionary<string, string>
            {
                ["orderId"] = order.Id.ToString(),
                ["tenantId"] = tenantId,
                ["consumerId"] = consumerId,
                ["lineItemCount"] = order.LineItems.Count.ToString()
            });

            return Results.Created($"/orders/{order.Id}", order);
        });

        // PATCH /orders/{id}/status
        orders.MapPatch("/{id:guid}/status", async (
            Guid id,
            UpdateOrderStatusRequest request,
            HttpContext context,
            IOrderService orderService) =>
        {
            var tenantId = context.Request.Headers["X-Tenant-Id"].FirstOrDefault() ?? "default";

            if (!Enum.TryParse<OrderStatus>(request.Status, true, out var status))
                return Results.BadRequest(new { error = $"Invalid status: {request.Status}" });

            var updated = await orderService.UpdateOrderStatusAsync(id, status, tenantId);
            return updated is null ? Results.NotFound() : Results.Ok(updated);
        });

        // DELETE /orders/{id}
        orders.MapDelete("/{id:guid}", async (
            Guid id,
            HttpContext context,
            IOrderService orderService) =>
        {
            var tenantId = context.Request.Headers["X-Tenant-Id"].FirstOrDefault() ?? "default";
            var deleted = await orderService.DeleteOrderAsync(id, tenantId);
            return deleted ? Results.NoContent() : Results.NotFound();
        });
    }

    public static void MapHealthEndpoints(this WebApplication app)
    {
        // /health — App Service health check path (set in appservice.bicep)
        // Returns 200 for App Service to keep instance in rotation
        app.MapGet("/health", () => Results.Ok(new
        {
            status = "healthy",
            timestamp = DateTime.UtcNow,
            version = "1.0.0"
        }));

        // /health/ready — used by slot swap verification in pipeline
        // Checks actual dependencies before declaring ready
        app.MapHealthChecks("/health/ready");

        // /health/live — liveness probe (is the process alive)
        app.MapGet("/health/live", () => Results.Ok(new { status = "alive" }));
    }
}