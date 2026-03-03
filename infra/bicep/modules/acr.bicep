// =============================================================================
// acr.bicep
// Azure Container Registry — Basic tier, admin disabled, MI pull
// WAF Security: no registry credentials, App Service pulls via Managed Identity
// =============================================================================

@description('Environment name')
param environmentName string

@description('Unique suffix for globally unique registry name')
param uniqueSuffix string

@description('Azure region')
param location string = resourceGroup().location

@description('App Service principal ID — granted AcrPull role')
param appServicePrincipalId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

// =============================================================================
// CONTAINER REGISTRY
// Basic tier — sufficient for portfolio project
// Admin account disabled — MI pull only (ADR-004)
// =============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'acr${environmentName}${uniqueSuffix}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false // MI pull only — no username/password
    publicNetworkAccess: 'Enabled' // Basic tier doesn't support private endpoints
    // Note: Premium tier needed for private endpoint — cost justified only in prod
    zoneRedundancy: 'Disabled'
  }
}

// =============================================================================
// RBAC — AcrPull for App Service MI
// App Service pulls images using its MI — no registry credentials stored
// =============================================================================

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acrPullRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acrPullRoleId, appServicePrincipalId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      acrPullRoleId
    )
    principalId: appServicePrincipalId
    principalType: 'ServicePrincipal'
    description: 'App Service MI — pull container images from ACR'
  }
}

// =============================================================================
// DIAGNOSTIC SETTINGS
// =============================================================================

resource acrDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-acr-orderflow-${environmentName}'
  scope: acr
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
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

output acrId          string = acr.id
output acrName        string = acr.name
output acrLoginServer string = acr.properties.loginServer
