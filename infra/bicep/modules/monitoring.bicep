// =============================================================================
// monitoring.bicep
// Log Analytics Workspace + Application Insights
// WAF: Operational Excellence — instrument before deploying the app
//
// NOTE: KQL alert rules intentionally excluded from this module.
// The 'requests' table in Log Analytics only exists after Application Insights
// receives its first telemetry. Deploying alert rules against a non-existent
// table causes BadRequest errors at deployment time.
// Alert rules are added in alerts.bicep — deployed in Phase 5 after app is live.
// =============================================================================

@description('Environment name')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

@description('Daily data cap in GB — prevents runaway ingestion costs in dev')
@minValue(1)
@maxValue(100)
param dailyQuotaGb int = 2

@description('Retention in days')
@allowed([30, 60, 90, 120, 180, 270, 365])
param retentionDays int = 30

// =============================================================================
// LOG ANALYTICS WORKSPACE
// =============================================================================

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-orderflow-${environmentName}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// APPLICATION INSIGHTS
// Workspace-based (classic App Insights is deprecated — never use it)
// Linked to Log Analytics so all telemetry queryable alongside Azure logs
// =============================================================================

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-orderflow-${environmentName}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    // 100% sampling in dev — every request captured, no data loss during testing
    // Set to null in prod to enable adaptive sampling and reduce ingestion cost
    SamplingPercentage: environmentName == 'prod' ? null : 100
    RetentionInDays: retentionDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// ACTION GROUP
// Notification target for alerts — email only for now
// Extend in Phase 5: add webhook for Teams/PagerDuty
// =============================================================================

resource alertActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-orderflow-${environmentName}'
  location: 'global'
  properties: {
    groupShortName: 'orderflow'
    enabled: true
    emailReceivers: []
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output logAnalyticsWorkspaceId   string = logAnalytics.id
output logAnalyticsWorkspaceName string = logAnalytics.name
output appInsightsId             string = appInsights.id
output appInsightsName           string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output actionGroupId             string = alertActionGroup.id
