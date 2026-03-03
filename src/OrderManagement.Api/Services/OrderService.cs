using Microsoft.Extensions.Caching.Memory;
using Microsoft.EntityFrameworkCore;
using OrderManagement.Api.Data;
using OrderManagement.Api.Models;

namespace OrderManagement.Api.Services;

public class OrderService : IOrderService
{
    private readonly OrderDbContext _db;
    private readonly IMemoryCache _cache;
    private readonly ILogger<OrderService> _logger;
    private static readonly TimeSpan CacheTtl = TimeSpan.FromSeconds(30);

    public OrderService(OrderDbContext db, IMemoryCache cache, ILogger<OrderService> logger)
    {
        _db = db;
        _cache = cache;
        _logger = logger;
    }

    public async Task<IEnumerable<OrderResponse>> GetOrdersAsync(string tenantId, int page, int pageSize)
    {
        var cacheKey = $"orders:{tenantId}:page:{page}:size:{pageSize}";
        if (_cache.TryGetValue(cacheKey, out IEnumerable<OrderResponse>? cached))
            return cached!;

        var orders = await _db.Orders
            .Where(o => o.TenantId == tenantId)
            .OrderByDescending(o => o.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Include(o => o.LineItems)
            .AsNoTracking()
            .Select(o => MapToResponse(o))
            .ToListAsync();

        _cache.Set(cacheKey, orders, CacheTtl);
        return orders;
    }

    public async Task<OrderResponse?> GetOrderByIdAsync(Guid id, string tenantId)
    {
        var cacheKey = $"order:{id}:{tenantId}";
        if (_cache.TryGetValue(cacheKey, out OrderResponse? cached))
            return cached;

        var order = await _db.Orders
            .Include(o => o.LineItems)
            .AsNoTracking()
            .FirstOrDefaultAsync(o => o.Id == id && o.TenantId == tenantId);

        if (order is null) return null;

        var response = MapToResponse(order);
        _cache.Set(cacheKey, response, CacheTtl);
        return response;
    }

    public async Task<OrderResponse> CreateOrderAsync(CreateOrderRequest request, string tenantId, string consumerId)
    {
        var order = new Order
        {
            CustomerId = request.CustomerId,
            CustomerName = request.CustomerName,
            TenantId = tenantId,
            CallerIdentity = consumerId,
            Status = OrderStatus.Pending,
            LineItems = request.LineItems.Select(l => new LineItem
            {
                ProductId = l.ProductId,
                ProductName = l.ProductName,
                Quantity = l.Quantity,
                UnitPrice = l.UnitPrice
            }).ToList()
        };

        order.TotalAmount = order.LineItems.Sum(l => l.LineTotal);
        _db.Orders.Add(order);
        await _db.SaveChangesAsync();

        for (int p = 1; p <= 10; p++)
            _cache.Remove($"orders:{tenantId}:page:{p}:size:20");

        _logger.LogInformation("Order {OrderId} created for tenant {TenantId} by {ConsumerId}",
            order.Id, tenantId, consumerId);

        return MapToResponse(order);
    }

    public async Task<OrderResponse?> UpdateOrderStatusAsync(Guid id, OrderStatus status, string tenantId)
    {
        var order = await _db.Orders
            .Include(o => o.LineItems)
            .FirstOrDefaultAsync(o => o.Id == id && o.TenantId == tenantId);

        if (order is null) return null;

        order.Status = status;
        order.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        _cache.Remove($"order:{id}:{tenantId}");
        return MapToResponse(order);
    }

    public async Task<bool> DeleteOrderAsync(Guid id, string tenantId)
    {
        var order = await _db.Orders
            .FirstOrDefaultAsync(o => o.Id == id && o.TenantId == tenantId);

        if (order is null) return false;

        _db.Orders.Remove(order);
        await _db.SaveChangesAsync();
        _cache.Remove($"order:{id}:{tenantId}");
        return true;
    }

    private static OrderResponse MapToResponse(Order order) => new(
        order.Id,
        order.CustomerId,
        order.CustomerName,
        order.Status.ToString(),
        order.LineItems.Select(l => new LineItemResponse(
            l.Id, l.ProductId, l.ProductName, l.Quantity, l.UnitPrice, l.LineTotal
        )).ToList(),
        order.TotalAmount,
        order.CreatedAt
    );
}