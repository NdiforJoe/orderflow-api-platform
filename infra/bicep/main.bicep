targetScope = 'subscription'

@description('Environment name')
@allowed(['dev', 'prod'])
param environmentName string = 'dev'

@description('Primary Azure region')
param location string = 'eastus2'

@description('Unique suffix for globally unique resource names')
@maxLength(6)
param uniqueSuffix string

@description('Entra ID Object ID for SQL admin group')
param sqlAdminObjectId string = ''

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

module apim 'modules/apim.bicep' = {
  name: 'deploy-apim-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
    apimSubnetId: networking.outputs.apimSubnetId
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    backendHostname: appService.outputs.webAppHostname
  }
}

module sql 'modules/sql.bicep' = {
  name: 'deploy-sql-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
    dataSubnetId: networking.outputs.dataSubnetId
    sqlDnsZoneId: networking.outputs.sqlDnsZoneId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    sqlAdminObjectId: sqlAdminObjectId != '' ? sqlAdminObjectId : subscription().tenantId
    sqlAdminDisplayName: 'orderflow-sql-admins'
  }
}

module redis 'modules/redis.bicep' = {
  name: 'deploy-redis-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
    dataSubnetId: networking.outputs.dataSubnetId
    redisDnsZoneId: networking.outputs.redisDnsZoneId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

module serviceBus 'modules/servicebus.bicep' = {
  name: 'deploy-servicebus-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
    integrationSubnetId: networking.outputs.integrationSubnetId
    serviceBusDnsZoneId: networking.outputs.serviceBusDnsZoneId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    appServicePrincipalId: appService.outputs.webAppPrincipalId
  }
}

module acr 'modules/acr.bicep' = {
  name: 'deploy-acr-${environmentName}'
  scope: workloadRg
  params: {
    environmentName: environmentName
    uniqueSuffix: uniqueSuffix
    location: location
    appServicePrincipalId: appService.outputs.webAppPrincipalId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// RBAC — Key Vault Secrets User for App Service MIs
module prodSlotKvRbac 'modules/rbac.bicep' = {
  name: 'deploy-prod-kv-rbac-${environmentName}'
  scope: workloadRg
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: appService.outputs.webAppPrincipalId
    roleDescription: 'Production App Service MI - Key Vault Secrets User'
  }
}

module stagingSlotKvRbac 'modules/rbac.bicep' = {
  name: 'deploy-staging-kv-rbac-${environmentName}'
  scope: workloadRg
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: appService.outputs.stagingSlotPrincipalId
    roleDescription: 'Staging slot MI - Key Vault Secrets User'
  }
}

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
output webAppName        string = appService.outputs.webAppName
output webAppHostname    string = appService.outputs.webAppHostname
output webAppPrincipalId string = appService.outputs.webAppPrincipalId
output apimName          string = apim.outputs.apimName
output apimGatewayUrl    string = apim.outputs.apimGatewayUrl
output sqlServerName     string = sql.outputs.sqlServerName
output sqlDatabaseName   string = sql.outputs.sqlDatabaseName
output redisName         string = redis.outputs.redisName
output serviceBusName    string = serviceBus.outputs.serviceBusName
output acrLoginServer    string = acr.outputs.acrLoginServer
