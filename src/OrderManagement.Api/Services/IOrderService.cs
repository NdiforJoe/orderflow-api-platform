using OrderManagement.Api.Models;

namespace OrderManagement.Api.Services;

public interface IOrderService
{
    Task<IEnumerable<OrderResponse>> GetOrdersAsync(string tenantId, int page, int pageSize);
    Task<OrderResponse?> GetOrderByIdAsync(Guid id, string tenantId);
    Task<OrderResponse> CreateOrderAsync(CreateOrderRequest request, string tenantId, string consumerId);
    Task<OrderResponse?> UpdateOrderStatusAsync(Guid id, OrderStatus status, string tenantId);
    Task<bool> DeleteOrderAsync(Guid id, string tenantId);
}