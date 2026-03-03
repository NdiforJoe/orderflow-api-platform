// =============================================================================
// Order.cs — Domain models
// Deliberately simple — focus is architecture not business logic
// =============================================================================

namespace OrderManagement.Api.Models;

public class Order
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string CustomerId { get; set; } = string.Empty;
    public string CustomerName { get; set; } = string.Empty;
    public OrderStatus Status { get; set; } = OrderStatus.Pending;
    public List<LineItem> LineItems { get; set; } = [];
    public decimal TotalAmount { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }
    // Populated from APIM header X-Tenant-Id — multi-tenant aware
    public string TenantId { get; set; } = string.Empty;
    // Populated from APIM header X-Consumer-Id — audit trail
    public string CallerIdentity { get; set; } = string.Empty;
}

public class LineItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrderId { get; set; }
    public string ProductId { get; set; } = string.Empty;
    public string ProductName { get; set; } = string.Empty;
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal LineTotal => Quantity * UnitPrice;
}

public enum OrderStatus
{
    Pending,
    Confirmed,
    Processing,
    Shipped,
    Delivered,
    Cancelled
}

// DTOs — never expose EF entities directly to API consumers
public record CreateOrderRequest(
    string CustomerId,
    string CustomerName,
    List<CreateLineItemRequest> LineItems
);

public record CreateLineItemRequest(
    string ProductId,
    string ProductName,
    int Quantity,
    decimal UnitPrice
);

public record OrderResponse(
    Guid Id,
    string CustomerId,
    string CustomerName,
    string Status,
    List<LineItemResponse> LineItems,
    decimal TotalAmount,
    DateTime CreatedAt
);

public record LineItemResponse(
    Guid Id,
    string ProductId,
    string ProductName,
    int Quantity,
    decimal UnitPrice,
    decimal LineTotal
);

public record UpdateOrderStatusRequest(string Status);