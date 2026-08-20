@description('Container App resource ID')
param containerAppId string

@description('Environment name for naming')
param environmentName string

@description('Location for the scheduled query rule')
param location string

@description('Log Analytics workspace resource ID — scope for the revision health query')
param workspaceId string

// ============================================================
// Action Group (minimal - SRE Agent picks up alerts via managed resources)
// ============================================================
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-sre-lab-${environmentName}'
  location: 'global'
  properties: {
    groupShortName: 'SRELabAG'
    enabled: true
  }
}

// ============================================================
// Single alert: HTTP 5xx errors on Container App
// One alert keeps it clean — the agent investigates the root cause
// (memory leak, OOM, code bug) regardless of which symptom triggered it.
// ============================================================
resource http5xxAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-http-5xx-${environmentName}'
  location: 'global'
  properties: {
    description: 'Alert when Grubify returns HTTP 5xx errors — triggers SRE Agent investigation'
    severity: 3
    enabled: true
    scopes: [
      containerAppId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'http5xx'
          metricName: 'Requests'
          metricNamespace: 'microsoft.app/containerapps'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          dimensions: [
            {
              name: 'statusCodeCategory'
              operator: 'Include'
              values: [
                '5xx'
              ]
            }
          ]
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ============================================================
// Scenario 1-C — response latency
// Baseline on this app is 1-3 ms, so 200 ms is unambiguous. The scenario is not
// reproducible on the stock Grubify endpoints (see README 6.10) — the rule is
// here for environments whose endpoints actually do work.
// ============================================================
resource latencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-latency-${environmentName}'
  location: 'global'
  properties: {
    description: 'Grubify response time is far above the 1-3ms baseline — triggers SRE Agent investigation'
    severity: 2
    enabled: true
    scopes: [
      containerAppId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'responseTime'
          metricName: 'ResponseTime'
          metricNamespace: 'microsoft.app/containerapps'
          operator: 'GreaterThan'
          threshold: 200
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// A separate rule on purpose: the agent's reinvestigation cooldown is per alert
// rule, so a config-error run gets its own investigation instead of being merged
// into the 5xx thread.
// ============================================================
resource revisionHealthAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-revision-unhealthy-${environmentName}'
  location: location
  properties: {
    description: 'Grubify revision cannot serve traffic (port mismatch / unhealthy replica) — triggers SRE Agent investigation'
    severity: 2
    enabled: true
    scopes: [
      workspaceId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    criteria: {
      allOf: [
        {
          query: '''
ContainerAppSystemLogs_CL
| where ContainerAppName_s startswith "ca-grubify"
| where Reason_s has "PortMismatch" or Reason_s == "ReplicaUnhealthy" or Reason_s has "Crash"
| summarize Events = count() by ContainerAppName_s, RevisionName_s, Reason_s
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 2
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

