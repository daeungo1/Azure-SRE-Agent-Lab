# Cost Guardrail Review

A read-only sweep of the workshop resource group. **This skill never modifies resources** — it reports.

## What to inspect

### 1. Container App sizing vs. actual usage

Compare the configured limits against observed peak usage over the last 7 days. A container using less
than 40% of its memory limit at peak is a resize candidate.

```bash
az containerapp list -g <rg> \
  --query "[].{name:name, cpu:properties.template.containers[0].resources.cpu, mem:properties.template.containers[0].resources.memory, min:properties.template.scale.minReplicas, max:properties.template.scale.maxReplicas}" -o table
```

> Note for this lab: the API container was intentionally scaled to `1.0 / 2.0Gi` by the agent during the
> incident demo. Flag it, but do **not** recommend reverting it without checking the incident history first.

### 2. Idle minimum replicas

`minReplicas >= 1` bills continuously. For non-production or demo workloads that tolerate cold start,
`minReplicas = 0` is usually the single largest saving.

### 3. Log Analytics ingestion

Ingestion is the dominant cost in most observability setups.

```kusto
Usage
| where TimeGenerated > ago(30d)
| where IsBillable == true
| summarize GB = sum(Quantity) / 1000 by DataType
| order by GB desc
```

Flag any table contributing more than 20% of total volume and check whether its retention or sampling
can be reduced.

### 4. Orphaned resources

Registries with no recent pulls, workspaces with no connected sources, and unused action groups.

## Output format

Produce a table sorted by estimated monthly saving, and state the confidence for each item:

| Resource | Finding | Suggested action | Est. saving | Confidence | Risk |
|---|---|---|---|---|---|

End with one sentence naming the single highest-value action. Do not propose changes to resources that
are currently part of an open incident.
