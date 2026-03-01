// =============================================================================
// keyvault.bicep
// Key Vault with RBAC, private endpoint, and diagnostic settings
// ADR-004: Secret-free architecture - all secrets fetched via Managed Identity
// =============================================================================

@description('Environment name')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

@description('Unique suffix to ensure globally unique Key Vault name')
param uniqueSuffix string

@description('Subnet ID for private endpoint')
param privateEndpointSubnetId string

@description('Hub VNet ID for private endpoint network interface')
param hubVnetId string

@description('Private DNS Zone ID for Key Vault')
param keyVaultDnsZoneId string

@description('App Service Managed Identity principal ID - granted Secrets User role')
param appServicePrincipalId string = ''

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

// =============================================================================
// KEY VAULT
// RBAC mode (not vault access policies) - aligns to zero-trust principle
// =============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-orderflow-${environmentName}-${uniqueSuffix}'
  location: location
  properties: {
    sku: {
      family: 'A'
      // Standard sufficient for secrets - Premium adds HSM (not required here)
      name: 'standard'
    }
    tenantId: subscription().tenantId
    // RBAC mode: permissions managed via Azure RBAC, not vault access policies
    // Aligns to ADR-004 - no service principals with blanket Get/List on all secrets
    enableRbacAuthorization: true
    // Soft delete: 7 days minimum, prevents accidental permanent deletion
    enableSoftDelete: true
    softDeleteRetentionInDays: environmentName == 'prod' ? 90 : 7
    // Purge protection: prevents even admins from purging during retention period
    enablePurgeProtection: true
    // Network ACL: deny public access - all access via private endpoint
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    // Disable public network access entirely
    publicNetworkAccess: 'Disabled'
  }
}

// =============================================================================
// RBAC ASSIGNMENT
// App Service MI gets Key Vault Secrets User (read-only, specific secrets)
// NOT Key Vault Administrator - principle of least privilege
// =============================================================================

// Built-in role: Key Vault Secrets User
// Role ID: 4633458b-17de-408a-b874-0445c86b69e6
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource appServiceKvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (appServicePrincipalId != '') {
  // Deterministic GUID based on scope + role + principal
  name: guid(keyVault.id, keyVaultSecretsUserRoleId, appServicePrincipalId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: appServicePrincipalId
    principalType: 'ServicePrincipal'
    description: 'App Service MI - read secrets only, not administer'
  }
}

// =============================================================================
// PRIVATE ENDPOINT
// Key Vault accessible only from hub VNet shared services subnet
// =============================================================================

resource kvPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-kv-orderflow-${environmentName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-kv-orderflow-${environmentName}'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

// Register private endpoint in private DNS zone so VNet resources resolve it
resource kvDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  name: 'default'
  parent: kvPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: keyVaultDnsZoneId
        }
      }
    ]
  }
}

// =============================================================================
// DIAGNOSTIC SETTINGS
// All Key Vault operations logged - required for security audit trail
// =============================================================================

resource kvDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logAnalyticsWorkspaceId != '') {
  name: 'diag-kv-orderflow-${environmentName}'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        // Who accessed what secret, when, from where - full audit trail
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

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
