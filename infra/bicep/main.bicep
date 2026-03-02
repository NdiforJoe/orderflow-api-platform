// =============================================================================
// main.bicep — Subscription-scope orchestrator
// Phases deployed: Networking, Key Vault, Monitoring, App Service
// =============================================================================

targetScope = 'subscription'

@description('Environment name')
@allowed(['dev', 'prod'])
param environmentName string = 'dev'

@description('Primary Azure region')
param location string = 'eastus2'

@description('Unique suffix for globally unique resource names')
@maxLength(6)
param uniqueSuffix string

@description('Your Entra ID Object ID — granted Key Vault Admin for secret seeding')
param adminObjectId string

@description('Alert notification email (optional)')
param alertEmailAddress string = ''

// =============================================================================
// VARIABLES
// =============================================================================

var networkRgName  = 'rg-orderflow-network-${environmentName}'
var workloadRgName = 'rg-orderflow-${environmentName}'
var tags = {
  Environment: environmentName
  Project: 'orderflow-api-platform'
  ManagedBy: 'Bicep'
  WAF: 'true'
}

// =============================================================================
// RESOURCE GROUPS
// =============================================================================

resource networkRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: networkRgName
  location: location
  tags: tags
}

resource workloadRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: workloadRgName
  location: location
  tags: tags
}

// =============================================================================
// NETWORKING
// =============================================================================

module networking 'modules/networking.bicep' = {
  name: 'deploy-networking-${environmentName}'
  scope: networkRg
  params: {
    environmentName: environmentName
    location: location
  }
}

// =============================================================================
// MONITORING — deployed before App Service so connection string is ready
// =============================================================================

module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
    alertEmailAddress: alertEmailAddress
  }
}

// =============================================================================
// KEY VAULT
// =============================================================================

module keyVault 'modules/keyvault.bicep' = {
  name: 'deploy-keyvault-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
    uniqueSuffix: uniqueSuffix
    privateEndpointSubnetId: networking.outputs.sharedServicesSubnetId
    hubVnetId: networking.outputs.hubVnetId
    keyVaultDnsZoneId: networking.outputs.keyVaultDnsZoneId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    // App Service principal ID wired in after App Service module runs
    appServicePrincipalId: appService.outputs.webAppPrincipalId
  }
}

// =============================================================================
// APP SERVICE
// Depends on monitoring (needs connection string) and networking (needs subnet)
// =============================================================================

module appService 'modules/appservice.bicep' = {
  name: 'deploy-appservice-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
    appSubnetId: networking.outputs.appSubnetId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    keyVaultUri: keyVault.outputs.keyVaultUri
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// =============================================================================
// RBAC — Key Vault Secrets User for staging slot MI
// Production slot RBAC is handled inside keyvault.bicep
// =============================================================================

module stagingSlotKvRbac 'modules/rbac.bicep' = {
  name: 'deploy-staging-kv-rbac-${environmentName}'
  scope: workloadRg
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: appService.outputs.stagingSlotPrincipalId
    roleDescription: 'Staging slot MI - read KV secrets for blue-green deployments'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output networkRgName        string = networkRg.name
output workloadRgName       string = workloadRg.name
output hubVnetId            string = networking.outputs.hubVnetId
output spokeVnetId          string = networking.outputs.spokeVnetId
output keyVaultName         string = keyVault.outputs.keyVaultName
output keyVaultUri          string = keyVault.outputs.keyVaultUri
output logAnalyticsName     string = monitoring.outputs.logAnalyticsWorkspaceName
output appInsightsName      string = monitoring.outputs.appInsightsName
output webAppName           string = appService.outputs.webAppName
output webAppHostname       string = appService.outputs.webAppHostname
output webAppPrincipalId    string = appService.outputs.webAppPrincipalId
