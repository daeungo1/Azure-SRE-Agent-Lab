# Grubify OOM Triage

Use this skill when the Grubify API returns HTTP 5xx and memory pressure is suspected.
This is the exact failure mode reproduced by `scripts/break-app.sh` in this lab.

## When to use

- An Azure Monitor alert fires on `requests/failed` for `ca-grubify-*`
- Console logs contain `OutOfMemoryException`
- Container memory working set approaches the configured limit

## Diagnostic steps

1. **Confirm the blast radius.** Query App Insights for the failure rate and the top failing operations.

   ```kusto
   requests
   | where timestamp > ago(1h)
   | summarize total = count(), failed = countif(success == false) by operation_Name, bin(timestamp, 5m)
   | where failed > 0
   | order by timestamp desc
   ```

2. **Find the exception and its source location.** The stack trace identifies the exact file and line.

   ```kusto
   exceptions
   | where timestamp > ago(1h)
   | where type contains "OutOfMemory"
   | project timestamp, type, outerMessage, details
   | order by timestamp desc
   | take 20
   ```

3. **Correlate requests with memory.** Plot request volume against container memory working set using
   `PlotAreaChartWithCorrelation`. An OOM shows memory climbing monotonically until the process is killed,
   with 5xx appearing only after the limit is reached.

4. **Read the current sizing.** Never guess the current limits.

   ```bash
   az containerapp show -g <rg> -n <app> \
     --query "properties.template.containers[0].resources"
   ```

5. **Check replica restarts.** Repeated restarts within a short window confirm the container is being killed.

   ```kusto
   ContainerAppSystemLogs_CL
   | where TimeGenerated > ago(1h)
   | where Log_s has_any ("OOMKilled", "restart", "Killing")
   | order by TimeGenerated desc
   ```

## Remediation guidance

Size the fix from evidence, not from a default:

- If peak working set is within ~20% of the limit under normal load, **double the memory** and keep CPU
  proportional (Container Apps requires CPU:memory ratios such as `0.5 : 1Gi`, `1.0 : 2Gi`, `2.0 : 4Gi`).
- If memory grows without bound regardless of load, this is a **leak** — increasing the limit only delays
  the failure. Raise the limit to restore service, then file a code-level action item.
- Always restart the revision after resizing and verify recovery with a real request before closing.

## Verification

1. Confirm the new revision is `Healthy` / `Running`.
2. Issue a request against the previously failing endpoint and expect a 2xx.
3. Re-run the failure-rate query and confirm the error rate returns to baseline.
4. Only then acknowledge and close the alert.

## Reporting

Record in the incident report: peak memory, the limit before and after, the exception type with
`file:line`, the revision names before and after, and whether the root cause is sizing or a leak.
