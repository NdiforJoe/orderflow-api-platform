// =============================================================================
// redis.bicep
// Azure Cache for Redis — C1 Standard, private endpoint
// WAF Performance: cache-aside pattern, reduces SQL reads by ~70% for read-heavy workloads
// WAF Security: public access disabled, private endpoint only
// WAF Cost: C1 Standard ~$16/mo — C0 Basic rejected (no replication, no SLA)
// =============================================================================

@description('Environment name')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

@description('Data subnet ID for private endpoint')
param dataSubnetId string

@description('Redis private DNS zone ID')
param redisDnsZoneId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

// =============================================================================
// REDIS CACHE
// C1 Standard: 1GB, replication, daily backup, 99.9% SLA
// C0 Basic rejected: no replication, no SLA, not suitable even for dev
// =============================================================================

resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: 'redis-orderflow-${environmentName}'
  location: location
  properties: {
    sku: {
      name: 'Standard'
      family: 'C'
      capacity: 1 // C1 = 1GB
    }
    enableNonSslPort: false // SSL only — TLS enforced
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    redisConfiguration: {
      // Max memory policy: evict least recently used keys when memory is full
      // LRU is appropriate for cache-aside pattern — old entries evicted first
      'maxmemory-policy': 'allkeys-lru'
      // Enable keyspace notifications for cache invalidation events
      'notify-keyspace-events': 'Ex'
    }
  }
}

// =============================================================================
// PRIVATE ENDPOINT
// =============================================================================

resource redisPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-redis-orderflow-${environmentName}'
  location: location
  properties: {
    subnet: {
      id: dataSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-redis-orderflow-${environmentName}'
        properties: {
          privateLinkServiceId: redis.id
          groupIds: ['redisCache']
        }
      }
    ]
  }
}

resource redisDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  name: 'default'
  parent: redisPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-redis-cache-windows-net'
        properties: {
          privateDnsZoneId: redisDnsZoneId
        }
      }
    ]
  }
}

// =============================================================================
// DIAGNOSTIC SETTINGS
// =============================================================================

resource redisDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-redis-orderflow-${environmentName}'
  scope: redis
  properties: {
    workspaceId: logAnalyticsWorkspaceId
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

output redisId   string = redis.id
output redisName string = redis.name
output redisHostname string = redis.properties.hostName
output redisPort int = redis.properties.sslPort
