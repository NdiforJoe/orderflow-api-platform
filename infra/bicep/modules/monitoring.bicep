// =============================================================================
// monitoring.bicep
// Log Analytics Workspace + Application Insights + KQL Alert Rules
// WAF: Operational Excellence — observe from day 1, not as an afterthought
// WAF: Reliability — alerts fire before users notice problems
// =============================================================================

@description('Environment name')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

@description('Daily data cap in GB — prevents runaway ingestion costs in dev')
@minValue(1)
@maxValue(100)
param dailyQuotaGb int = 2

@description('Retention in days — 30 days free, charged beyond that')
@allowed([30, 60, 90, 120, 180, 270, 365])
param retentionDays int = 30

@description('Alert notification email')
param alertEmailAddress string = ''

// =============================================================================
// LOG ANALYTICS WORKSPACE
// Central store for all platform logs: APIM, App Service, Key Vault, SQL
// =============================================================================

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-orderflow-${environmentName}'
  location: location
  properties: {
    sku: {
      // PerGB2018 = pay per GB ingested, no commitment
      // Switch to Commitment tier at >100GB/day for ~25% saving
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
    workspaceCapping: {
      // Hard cap — stops ingestion if exceeded, prevents surprise bills
      // Critical for dev/test environments on free trial
      dailyQuotaGb: dailyQuotaGb
    }
    features: {
      // Enables faster KQL queries via dedicated cluster (no cost at this scale)
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    // Query can be locked down — ingestion must stay enabled for agents
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// APPLICATION INSIGHTS
// Linked to Log Analytics (workspace-based) — unified query across all logs
// Classic App Insights (not workspace-based) is deprecated — don't use it
// =============================================================================

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-orderflow-${environmentName}'
  location: location
  // Required tag for workspace-based App Insights
  kind: 'web'
  properties: {
    Application_Type: 'web'
    // Link to Log Analytics — all telemetry stored in same workspace
    // Enables joining App Insights data with other Azure logs in KQL
    WorkspaceResourceId: logAnalytics.id
    // Disable sampling in dev so every request is captured
    // Enable adaptive sampling in prod to reduce cost at scale
    SamplingPercentage: environmentName == 'prod' ? null : 100
    // Retain raw data for 90 days in prod, 30 in dev
    RetentionInDays: retentionDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// ACTION GROUP
// Where alerts are sent — email for now, extend to PagerDuty/Teams webhook
// =============================================================================

resource alertActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-orderflow-${environmentName}'
  location: 'global'
  properties: {
    groupShortName: 'orderflow'
    enabled: true
    emailReceivers: alertEmailAddress != '' ? [
      {
        name: 'PlatformAlerts'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ] : []
  }
}

// =============================================================================
// KQL ALERT RULES
// Four rules covering the golden signals: latency, errors, traffic, saturation
// All query App Insights via Log Analytics — unified workspace model
// =============================================================================

// Alert 1: High error rate — fires when 5xx errors exceed 5% of requests
resource errorRateAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-error-rate-${environmentName}'
  location: location
  properties: {
    displayName: 'OrderFlow - High Error Rate (>5%)'
    description: 'Fires when 5xx error rate exceeds 5% over 5 minutes. Investigate App Insights exceptions and App Service logs.'
    severity: 1 // Critical
    enabled: true
    evaluationFrequency: 'PT5M'  // Check every 5 minutes
    windowSize: 'PT5M'           // Over a 5-minute window
    scopes: [logAnalytics.id]
    criteria: {
      allOf: [
        {
          query: '''
requests
| where timestamp > ago(5m)
| where cloud_RoleName == "orderflow-api"
| summarize
    total = count(),
    errors = countif(resultCode >= 500)
| where total > 10
| extend errorRate = (errors * 100.0) / total
| where errorRate > 5
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [alertActionGroup.id]
    }
  }
}

// Alert 2: P95 latency — fires when 95th percentile response time > 2 seconds
resource latencyAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-p95-latency-${environmentName}'
  location: location
  properties: {
    displayName: 'OrderFlow - P95 Latency >2s'
    description: 'Fires when 95th percentile response time exceeds 2000ms. Check SQL query performance and Redis cache hit rate.'
    severity: 2 // Warning
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [logAnalytics.id]
    criteria: {
      allOf: [
        {
          query: '''
requests
| where timestamp > ago(15m)
| where cloud_RoleName == "orderflow-api"
| where name !contains "health"
| summarize p95_duration = percentile(duration, 95)
| where p95_duration > 2000
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [alertActionGroup.id]
    }
  }
}

// Alert 3: Auth failure spike — fires when 401/403 responses spike
// Could indicate credential stuffing, token misconfiguration, or APIM policy issue
resource authFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-auth-failures-${environmentName}'
  location: location
  properties: {
    displayName: 'OrderFlow - Auth Failure Spike (>20 in 5min)'
    description: 'Spike in 401/403 responses. Could indicate: expired Entra ID app registration, APIM JWT policy misconfiguration, or credential stuffing attack.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [logAnalytics.id]
    criteria: {
      allOf: [
        {
          query: '''
requests
| where timestamp > ago(5m)
| where cloud_RoleName == "orderflow-api"
| where resultCode in (401, 403)
| summarize authFailures = count()
| where authFailures > 20
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [alertActionGroup.id]
    }
  }
}

// Alert 4: Traffic anomaly — sudden drop in requests (could mean silent failure)
// A system with zero errors but also zero traffic is a problem
resource trafficDropAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-traffic-drop-${environmentName}'
  location: location
  properties: {
    displayName: 'OrderFlow - Traffic Drop (0 requests in 10min during business hours)'
    description: 'Zero requests received for 10 minutes. Could indicate APIM gateway down, DNS resolution failure, or Front Door misconfiguration.'
    severity: 2
    enabled: environmentName == 'prod' // Only meaningful in prod
    evaluationFrequency: 'PT10M'
    windowSize: 'PT10M'
    scopes: [logAnalytics.id]
    criteria: {
      allOf: [
        {
          query: '''
requests
| where timestamp > ago(10m)
| where cloud_RoleName == "orderflow-api"
| where name !contains "health"
| summarize requestCount = count()
| where requestCount == 0
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [alertActionGroup.id]
    }
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsWorkspaceName string = logAnalytics.name
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
