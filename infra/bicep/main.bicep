// =============================================================================
// main.bicep — Subscription-scope orchestrator
// Phase 3 partial: networking + monitoring + keyVault only
// App Service modules commented out pending quota approval (DSv3 request submitted)
// Uncomment appService, prodSlotKvRbac, stagingSlotKvRbac once quota approved
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

var networkRgName  = 'rg-orderflow-network-${environmentName}'
var workloadRgName = 'rg-orderflow-${environmentName}'
var tags = {
  Environment: environmentName
  Project: 'orderflow-api-platform'
  ManagedBy: 'Bicep'
  WAF: 'true'
}

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

module networking 'modules/networking.bicep' = {
  name: 'deploy-networking-${environmentName}'
  scope: networkRg
  params: {
    environmentName: environmentName
    location: location
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'deploy-keyvault-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
    uniqueSuffix: uniqueSuffix
    privateEndpointSubnetId: networking.outputs.sharedServicesSubnetId
    keyVaultDnsZoneId: networking.outputs.keyVaultDnsZoneId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// =============================================================================
// APP SERVICE — uncomment once DSv3 quota approved
// =============================================================================

// module appService 'modules/appservice.bicep' = {
//   name: 'deploy-appservice-${environmentName}'
//   scope: workloadRg
//   params: {
//     environmentName: environmentName
//     location: location
//     appSubnetId: networking.outputs.appSubnetId
//     appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
//     keyVaultUri: keyVault.outputs.keyVaultUri
//     logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
//   }
// }

// module prodSlotKvRbac 'modules/rbac.bicep' = {
//   name: 'deploy-prod-kv-rbac-${environmentName}'
//   scope: workloadRg
//   params: {
//     keyVaultName: keyVault.outputs.keyVaultName
//     principalId: appService.outputs.webAppPrincipalId
//     roleDescription: 'Production App Service MI - Key Vault Secrets User'
//   }
// }

// module stagingSlotKvRbac 'modules/rbac.bicep' = {
//   name: 'deploy-staging-kv-rbac-${environmentName}'
//   scope: workloadRg
//   params: {
//     keyVaultName: keyVault.outputs.keyVaultName
//     principalId: appService.outputs.stagingSlotPrincipalId
//     roleDescription: 'Staging slot MI - Key Vault Secrets User'
//   }
// }

// =============================================================================
// OUTPUTS
// =============================================================================

output networkRgName     string = networkRg.name
output workloadRgName    string = workloadRg.name
output hubVnetId         string = networking.outputs.hubVnetId
output spokeVnetId       string = networking.outputs.spokeVnetId
output keyVaultName      string = keyVault.outputs.keyVaultName
output keyVaultUri       string = keyVault.outputs.keyVaultUri
output logAnalyticsName  string = monitoring.outputs.logAnalyticsWorkspaceName
output appInsightsName   string = monitoring.outputs.appInsightsName
