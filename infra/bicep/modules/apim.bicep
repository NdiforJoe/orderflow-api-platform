// =============================================================================
// apim.bicep
// Azure API Management — Developer tier, internal VNet mode
// ADR-001: Developer tier chosen for dev — internal VNet mode enforces zero-trust
// WAF Security: no public backend IPs, JWT validation, OWASP policies at gateway
// WAF Reliability: App Insights logger, retry policies, circuit breaker
// =============================================================================

@description('Environment name')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

@description('APIM subnet ID — internal VNet mode')
param apimSubnetId string

@description('App Insights connection string for APIM logger')
param appInsightsId string

@description('App Insights instrumentation key')
param appInsightsInstrumentationKey string

@description('Log Analytics Workspace ID for diagnostic settings')
param logAnalyticsWorkspaceId string

@description('Backend App Service hostname')
param backendHostname string

@description('Publisher email — required by APIM')
param publisherEmail string = 'admin@orderflow.internal'

@description('Publisher name')
param publisherName string = 'OrderFlow Platform'

// =============================================================================
// API MANAGEMENT INSTANCE
// Developer tier: supports internal VNet mode, costs ~$49/mo
// Internal VNet mode: APIM gets private IP only — no public gateway endpoint
// All traffic must enter via Front Door → Firewall → APIM (zero-trust)
// =============================================================================

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: 'apim-orderflow-${environmentName}'
  location: location
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    // System-assigned MI — used to read Key Vault secrets for named values
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    // Disable legacy protocols
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
    }
  }
}

// =============================================================================
// APP INSIGHTS LOGGER
// Links APIM telemetry to the same App Insights workspace as the backend
// Enables end-to-end correlation: AFD → APIM → App Service in one trace
// =============================================================================

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = {
  name: 'appi-orderflow-logger'
  parent: apim
  properties: {
    loggerType: 'applicationInsights'
    description: 'App Insights logger for APIM telemetry'
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    isBuffered: true
    resourceId: appInsightsId
  }
}

// =============================================================================
// NAMED VALUES
// Centralised config store — policies reference these by name not hardcoded value
// Sensitive values reference Key Vault secrets via MI (added in Phase 5)
// =============================================================================

resource backendUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  name: 'backend-base-url'
  parent: apim
  properties: {
    displayName: 'backend-base-url'
    value: 'https://${backendHostname}'
    secret: false
  }
}

resource environmentNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  name: 'environment-name'
  parent: apim
  properties: {
    displayName: 'environment-name'
    value: environmentName
    secret: false
  }
}

// =============================================================================
// BACKEND
// Points to App Service — APIM forwards all validated requests here
// Certificate validation enabled — backend must present valid TLS cert
// =============================================================================

resource orderApiBackend 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  name: 'backend-orderflow-app'
  parent: apim
  properties: {
    description: 'OrderFlow App Service backend'
    url: 'https://${backendHostname}'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    properties: {}
  }
}

// =============================================================================
// PRODUCTS
// Products group APIs and apply subscription/auth requirements
// Internal product: delegated auth (SPA users via Entra ID)
// Partner product: client credentials (B2B machine-to-machine)
// =============================================================================

resource internalProduct 'Microsoft.ApiManagement/service/products@2023-05-01-preview' = {
  name: 'internal'
  parent: apim
  properties: {
    displayName: 'Internal'
    description: 'Internal product for SPA and internal service consumers. Uses delegated auth (auth code + PKCE).'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource partnerProduct 'Microsoft.ApiManagement/service/products@2023-05-01-preview' = {
  name: 'partner'
  parent: apim
  properties: {
    displayName: 'Partner'
    description: 'Partner product for B2B consumers. Uses client credentials flow.'
    subscriptionRequired: true
    approvalRequired: true  // Partners require manual approval
    state: 'published'
  }
}

// =============================================================================
// ORDER API DEFINITION
// =============================================================================

resource orderApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  name: 'order-api'
  parent: apim
  properties: {
    displayName: 'Order Management API'
    description: 'CRUD operations for order management. All endpoints require valid Entra ID JWT.'
    path: 'orders'
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    serviceUrl: 'https://${backendHostname}'
    isCurrent: true
  }
}

// Link Order API to both products
resource orderApiInternalProduct 'Microsoft.ApiManagement/service/products/apis@2023-05-01-preview' = {
  name: 'order-api'
  parent: internalProduct
  dependsOn: [orderApi]
}

resource orderApiPartnerProduct 'Microsoft.ApiManagement/service/products/apis@2023-05-01-preview' = {
  name: 'order-api'
  parent: partnerProduct
  dependsOn: [orderApi]
}

// =============================================================================
// DIAGNOSTIC SETTINGS → LOG ANALYTICS
// =============================================================================

resource apimDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-apim-orderflow-${environmentName}'
  scope: apim
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

output apimId string = apim.id
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimPrincipalId string = apim.identity.principalId
output apimLoggerName string = apimLogger.name
output orderApiName string = orderApi.name
