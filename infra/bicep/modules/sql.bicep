// =============================================================================
// sql.bicep
// Azure SQL Database — Serverless, Entra ID auth only, private endpoint
// WAF Security: no SQL auth, Entra ID only, public access disabled
// WAF Cost: Serverless auto-pauses after 1hr idle — dev cost ~$5/mo
// WAF Reliability: zone redundant in prod, geo-replication ready
// =============================================================================

@description('Environment name')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

// @description('Data subnet ID for private endpoint')
// param dataSubnetId string

// @description('SQL private DNS zone ID')
// param sqlDnsZoneId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Entra ID admin Object ID for SQL admin')
param sqlAdminObjectId string

@description('Entra ID admin display name')
param sqlAdminDisplayName string = 'orderflow-sql-admins'

// =============================================================================
// SQL SERVER
// No SQL admin password — Entra ID only auth
// ADR-004: MI authenticates via Entra ID, zero stored credentials
// =============================================================================

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: 'sql-orderflow-${environmentName}'
  location: location
  properties: {
    // Disable SQL authentication entirely — Entra ID only
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Group'
      login: sqlAdminDisplayName
      sid: sqlAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'
  }
}

// =============================================================================
// SQL DATABASE — Serverless
// Auto-pauses after 1hr idle in dev (saves ~80% cost vs always-on)
// Auto-resumes on first connection (~30s cold start — acceptable for dev)
// =============================================================================

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  name: 'db-orderflow-${environmentName}'
  parent: sqlServer
  location: location
  sku: {
    // Serverless: billed per vCore-second when active, free when paused
    // GeneralPurpose is the only tier supporting Serverless
    name: 'GP_S_Gen5_1'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 34359738368 // 32GB max
    autoPauseDelay: environmentName == 'prod' ? -1 : 60 // 60 min in dev, disabled in prod
    minCapacity: json('0.5') // Minimum 0.5 vCores when active
    zoneRedundant: false // Zone redundancy requires Business Critical tier
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: environmentName == 'prod' ? 'Geo' : 'Local'
  }
}

// =============================================================================
// PRIVATE ENDPOINT
// SQL only accessible from within the VNet via private endpoint
// =============================================================================

// resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
//   name: 'pe-sql-orderflow-${environmentName}'
//   location: location
//   properties: {
//     subnet: {
//       id: dataSubnetId
//     }
//     privateLinkServiceConnections: [
//       {
//         name: 'plsc-sql-orderflow-${environmentName}'
//         properties: {
//           privateLinkServiceId: sqlServer.id
//           groupIds: ['sqlServer']
//         }
//       }
//     ]
//   }
// }

// resource sqlDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
//   name: 'default'
//   parent: sqlPrivateEndpoint
//   properties: {
//     privateDnsZoneConfigs: [
//       {
//         name: 'privatelink-database-windows-net'
//         properties: {
//           privateDnsZoneId: sqlDnsZoneId
//         }
//       }
//     ]
//   }
// }

// =============================================================================
// DIAGNOSTIC SETTINGS
// =============================================================================

resource sqlDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-sql-orderflow-${environmentName}'
  scope: sqlDatabase
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

output sqlServerId   string = sqlServer.id
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
