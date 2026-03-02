// =============================================================================
// rbac.bicep
// Reusable Key Vault Secrets User role assignment
// Separated from keyvault.bicep to avoid circular dependency:
// keyvault needs appService principalId, appService needs keyVault URI
// main.bicep resolves the cycle by calling this module after both are deployed
// =============================================================================

@description('Key Vault name to scope the role assignment to')
param keyVaultName string

@description('Principal ID to assign the role to')
param principalId string

@description('Description for audit trail')
param roleDescription string = ''

// Built-in role: Key Vault Secrets User (read-only)
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, keyVaultSecretsUserRoleId, principalId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      keyVaultSecretsUserRoleId
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: roleDescription
  }
}
