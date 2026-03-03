using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.ApplicationInsights;

namespace OrderManagement.Api.Services;

// Simple health check confirming App Insights telemetry client is initialised
public class AppInsightsHealthCheck : IHealthCheck
{
    private readonly TelemetryClient _telemetry;

    public AppInsightsHealthCheck(TelemetryClient telemetry)
    {
        _telemetry = telemetry;
    }

    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var isHealthy = !string.IsNullOrEmpty(
            _telemetry.TelemetryConfiguration.ConnectionString);

        return Task.FromResult(isHealthy
            ? HealthCheckResult.Healthy("App Insights connected")
            : HealthCheckResult.Degraded("App Insights connection string missing"));
    }
}

// Sets cloud role name so KQL queries filter by "orderflow-api"
// Without this all App Insights telemetry shows as unnamed
public class CloudRoleNameInitializer : Microsoft.ApplicationInsights.Extensibility.ITelemetryInitializer
{
    private readonly string _roleName;
    public CloudRoleNameInitializer(string roleName) => _roleName = roleName;

    public void Initialize(Microsoft.ApplicationInsights.Channel.ITelemetry telemetry)
    {
        telemetry.Context.Cloud.RoleName = _roleName;
    }
}