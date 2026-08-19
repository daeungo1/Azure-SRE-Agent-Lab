# Escalation and Autonomy Policy

Defines how far the agent may act on its own, and when a human must be involved.
The agent must follow this policy even when it has the technical permission to do more.

## Severity definitions

| Severity | Meaning | Example |
|---|---|---|
| Sev0 | Total outage, all users | API returns 5xx for every request |
| Sev1 | Major degradation, most users | Ordering fails, browsing works |
| Sev2 | Partial degradation | One endpoint failing, or latency beyond p99 target |
| Sev3 | Minor / contained | Elevated error rate within error budget |
| Sev4 | Informational | Trend worth watching, no user impact |

## What the agent may do without asking

- Any read: logs, metrics, configuration, revision history, deployment history
- Acknowledge and close Azure Monitor alerts
- Write incident reports and save notes to team memory
- Restart a revision **when** an out-of-memory or crash-loop condition is proven by logs
- Resize CPU/memory **when** the evidence gate passes and the change follows the sizing table

## What always requires a human

- Any change to a resource that is not the direct subject of the current incident
- Deleting anything
- Changing networking, identity, or RBAC
- Scaling `minReplicas` to 0 on a Tier 1 service
- A second remediation attempt after the first did not restore service — stop and escalate instead of
  trying variations
- Anything estimated to cost more than the current monthly spend of the resource group

## Escalation triggers

Escalate to a human immediately, without further attempts, when any of these is true:

1. The root cause is not identified within 15 minutes of investigation.
2. The remediation was applied and verification still fails.
3. The same incident has recurred within 24 hours — this is a systemic problem, not an incident.
4. The failure involves data loss, or the possibility of it.
5. The evidence is contradictory and the agent cannot decide between two causes.

When escalating, hand over: what is broken, what has been ruled out, what was attempted, and the single
most useful next step. Never escalate with only "investigation failed".

## Communication

- Report facts and timestamps in UTC.
- Distinguish "mitigated" (service restored) from "resolved" (cause removed). Do not use them
  interchangeably.
- If uncertain, say so. An honest "unconfirmed" is more useful to an on-call engineer than a confident
  guess.
