// =============================================================================
// main.bicep
// Orchestrates all modules. Deployed at subscription scope so it can
// create resource groups and deploy resources across them.
// =============================================================================

targetScope = 'subscription'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('Environment name - controls tier sizes and costs')
@allowed(['dev', 'prod'])
param environmentName string = 'dev'

@description('Primary Azure region')
param location string = 'eastus2'

@description('Unique suffix for globally unique resource names (storage, KV, ACR)')
@maxLength(6)
param uniqueSuffix string

@description('Your Entra ID Object ID - granted Key Vault Admin for initial secret seeding')
param adminObjectId string

// =============================================================================
// VARIABLES
// =============================================================================

var networkRgName = 'rg-orderflow-network-${environmentName}'
var workloadRgName = 'rg-orderflow-${environmentName}'
var tags = {
  Environment: environmentName
  Project: 'orderflow-api-platform'
  ManagedBy: 'Bicep'
  WAF: 'true'
}

// =============================================================================
// RESOURCE GROUPS
// Created at subscription scope so we can manage both RGs from one deployment
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
// NETWORKING MODULE
// Deploys to network RG: hub VNet, spoke VNet, NSGs, peering, DNS zones
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
// KEY VAULT MODULE
// Deploys to workload RG with private endpoint back into hub VNet
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
    // appServicePrincipalId passed once App Service is deployed (Phase 3)
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output networkRgName string = networkRg.name
output workloadRgName string = workloadRg.name
output hubVnetId string = networking.outputs.hubVnetId
output spokeVnetId string = networking.outputs.spokeVnetId
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
