// =============================================================================
// appservice.bicep
// App Service Plan + Web App + Managed Identity + VNet Integration + Slots
// ADR-002: App Service chosen over AKS — slots enable blue-green, lower ops overhead
// WAF: Reliability — staging slot, health checks, zone redundancy (prod)
// WAF: Security — system-assigned MI, no stored credentials, VNet-integrated
// =============================================================================

@description('Environment name')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

@description('App Service subnet ID for VNet integration')
param appSubnetId string

@description('App Insights connection string — injected as app setting')
param appInsightsConnectionString string

@description('Key Vault URI — app settings reference secrets from here')
param keyVaultUri string

@description('Log Analytics Workspace ID for diagnostic settings')
param logAnalyticsWorkspaceId string

// =============================================================================
// APP SERVICE PLAN
// B2 in dev: 2 cores, 3.5GB RAM, ~$13/month, supports slots
// Premium v3 P1v3 in prod: zone redundancy, dedicated hardware
// =============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-orderflow-${environmentName}'
  location: location
  sku: {
    // Free trial blocks Basic and Standard tiers (VM quota = 0)
    // P1v3 (PremiumV3) is permitted on free trial — dedicated infrastructure
    // Cost: ~$0.169/hr = ~$123/mo BUT we are deleting immediately after demo
    // For a short-lived portfolio demo this is acceptable
    // ADR-002 documents B2 as the intended dev tier for paid subscriptions
    name: 'P1v3'
    tier: 'PremiumV3'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux
    zoneRedundant: environmentName == 'prod' // Zone redundancy prod only
  }
}

// =============================================================================
// WEB APP
// .NET 8 on Linux, VNet-integrated, system-assigned MI
// =============================================================================

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'app-orderflow-${environmentName}'
  location: location
  kind: 'app,linux'
  identity: {
    // System-assigned: Azure manages lifecycle, auto-deleted when app deleted
    // ADR-004: No service principal credentials — MI authenticates to KV, SQL, SB
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true // Reject all HTTP — TLS enforcement (WAF Security)
    clientAffinityEnabled: false // Stateless API — no sticky sessions needed
    virtualNetworkSubnetId: appSubnetId // VNet integration — all egress through spoke
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      alwaysOn: true // Prevent cold starts — health checks need consistent response
      ftpsState: 'Disabled' // FTP disabled — deployment via pipeline only
      minTlsVersion: '1.2' // TLS 1.0/1.1 disabled
      http20Enabled: true
      // Health check path — App Service uses this for instance health
      // Also used by blue-green slot swap to verify before promoting
      healthCheckPath: '/health'
      appSettings: [
        {
          // App Insights — SDK reads this automatically, no code changes needed
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          // Key Vault URI — used to construct @Microsoft.KeyVault() references
          name: 'KEY_VAULT_URI'
          value: keyVaultUri
        }
        {
          // Environment name — used for environment-specific logic in code
          name: 'ENVIRONMENT'
          value: environmentName
        }
        {
          // Tells ASP.NET Core to use Production config (appsettings.Production.json)
          name: 'ASPNETCORE_ENVIRONMENT'
          value: environmentName == 'prod' ? 'Production' : 'Development'
        }
      ]
      // Connection strings injected via Key Vault references
      // Format: @Microsoft.KeyVault(SecretUri=https://kv-name.vault.azure.net/secrets/secret-name/)
      // App Service resolves these at runtime using the Managed Identity
      connectionStrings: [
        {
          name: 'DefaultConnection'
          connectionString: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/sql-connection-string/)'
          type: 'SQLAzure'
        }
      ]
      cors: {
        // Locked down — only allow APIM to call the backend
        // Backend should never be called directly from browsers
        allowedOrigins: []
        supportCredentials: false
      }
    }
    // Route all outbound traffic through VNet
    // Critical for zero-trust: without this, outbound bypasses NSGs
    vnetRouteAllEnabled: true
  }
}

// =============================================================================
// STAGING SLOT
// Blue-green deployment: new version deploys here, health checked, then swapped
// Swap is atomic — zero downtime, instant rollback by re-swapping
// ADR-002: This is the primary reason App Service was chosen over AKS for this workload
// =============================================================================

resource stagingSlot 'Microsoft.Web/sites/slots@2023-12-01' = {
  name: 'staging'
  parent: webApp
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: appSubnetId
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      alwaysOn: true
      healthCheckPath: '/health'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'KEY_VAULT_URI'
          value: keyVaultUri
        }
        {
          name: 'ENVIRONMENT'
          value: '${environmentName}-staging'
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Staging'
        }
      ]
      connectionStrings: [
        {
          name: 'DefaultConnection'
          connectionString: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/sql-connection-string/)'
          type: 'SQLAzure'
        }
      ]
    }
    vnetRouteAllEnabled: true
  }
}

// =============================================================================
// AUTO-SCALE (prod only)
// Scale out when CPU > 70% for 5 minutes, scale in when < 30% for 10 minutes
// WAF: Performance Efficiency — handle traffic spikes without manual intervention
// =============================================================================

resource autoScale 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (environmentName == 'prod') {
  name: 'autoscale-orderflow-${environmentName}'
  location: location
  properties: {
    enabled: true
    targetResourceUri: appServicePlan.id
    profiles: [
      {
        name: 'Default'
        capacity: {
          minimum: '3'
          maximum: '10'
          default: '3'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '2'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
  }
}

// =============================================================================
// DIAGNOSTIC SETTINGS
// Ship App Service logs to Log Analytics for unified querying
// =============================================================================

resource appDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-app-orderflow-${environmentName}'
  scope: webApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output appServicePlanId string = appServicePlan.id
output webAppId string = webApp.id
output webAppName string = webApp.name
output webAppHostname string = webApp.properties.defaultHostName
// Principal ID used by main.bicep to assign Key Vault Secrets User role
output webAppPrincipalId string = webApp.identity.principalId
output stagingSlotPrincipalId string = stagingSlot.identity.principalId
output stagingSlotName string = stagingSlot.name
