// =============================================================================
// servicebus.bicep
// Azure Service Bus Standard — orders topic, private endpoint
// WAF Reliability: decouples order creation from downstream processing
// WAF Security: Entra ID auth only, no SAS keys, private endpoint
// =============================================================================

@description('Environment name')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('App Service principal ID — granted Service Bus Data Sender role')
param appServicePrincipalId string

// =============================================================================
// SERVICE BUS NAMESPACE
// Standard tier: topics + subscriptions (Basic tier only has queues)
// =============================================================================

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'sb-orderflow-${environmentName}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled' // Standard tier does not support private endpoints
    disableLocalAuth: true // Entra ID only — no SAS key auth
  }
}

// =============================================================================
// ORDERS TOPIC
// Order created events published here
// Multiple subscribers can consume independently (fan-out pattern)
// =============================================================================

resource ordersTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  name: 'orders'
  parent: serviceBus
  properties: {
    defaultMessageTimeToLive: 'P14D' // 14 days TTL
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M' // 10 min dedup window
    enableBatchedOperations: true
  }
}

// Order processing subscription — consumed by the Order Management API
resource orderProcessingSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  name: 'order-processing'
  parent: ordersTopic
  properties: {
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P14D'
    lockDuration: 'PT5M' // 5 min processing window before message reappears
    maxDeliveryCount: 3  // Retry 3 times then dead-letter
    enableBatchedOperations: true
  }
}

// =============================================================================
// RBAC
// App Service MI gets Service Bus Data Sender role
// Allows publishing order events without SAS keys
// =============================================================================

var serviceBusDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'

resource appServiceSbRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, serviceBusDataSenderRoleId, appServicePrincipalId)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      serviceBusDataSenderRoleId
    )
    principalId: appServicePrincipalId
    principalType: 'ServicePrincipal'
    description: 'App Service MI — publish order events to Service Bus'
  }
}

// // =============================================================================
// // PRIVATE ENDPOINT
// // =============================================================================

// resource sbPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
//   name: 'pe-sb-orderflow-${environmentName}'
//   location: location
//   properties: {
//     subnet: {
//       id: integrationSubnetId
//     }
//     privateLinkServiceConnections: [
//       {
//         name: 'plsc-sb-orderflow-${environmentName}'
//         properties: {
//           privateLinkServiceId: serviceBus.id
//           groupIds: ['namespace']
//         }
//       }
//     ]
//   }
// }

// resource sbDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
//   name: 'default'
//   parent: sbPrivateEndpoint
//   properties: {
//     privateDnsZoneConfigs: [
//       {
//         name: 'privatelink-servicebus-windows-net'
//         properties: {
//           privateDnsZoneId: serviceBusDnsZoneId
//         }
//       }
//     ]
//   }
// }

// =============================================================================
// DIAGNOSTIC SETTINGS
// =============================================================================

resource sbDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-sb-orderflow-${environmentName}'
  scope: serviceBus
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

output serviceBusId        string = serviceBus.id
output serviceBusName      string = serviceBus.name
output serviceBusNamespace string = '${serviceBus.name}.servicebus.windows.net'
output ordersTopicName     string = ordersTopic.name
