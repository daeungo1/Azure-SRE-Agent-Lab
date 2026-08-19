# Grubify Service Level Objectives

The agent uses these targets to decide whether the service is healthy, and to assign a RAG status.
Without them, "the error rate is 2%" is not actionable.

## Service scope

| Component | Azure resource | Criticality |
|---|---|---|
| Grubify API | `ca-grubify-*` (Azure Container Apps) | Tier 1 — customer-facing ordering |
| Grubify Frontend | `ca-grubify-fe-*` (Azure Container Apps) | Tier 2 — degraded UX if down, API still usable |

## Objectives

| SLI | Target | Measurement window |
|---|---|---|
| Availability (non-5xx / total) | ≥ 99.5% | rolling 30 days |
| Error rate | < 1% | rolling 1 hour |
| Latency p95 | < 800 ms | rolling 1 hour |
| Latency p99 | < 2000 ms | rolling 1 hour |

## Error budget

99.5% over 30 days allows roughly **3 hours 39 minutes** of unavailability per month.

Budget policy:

- **< 50% consumed** — normal operation. Feature changes proceed.
- **50–90% consumed** — Amber. Reliability work takes priority over new features.
- **> 90% consumed** — Red. Change freeze except for fixes that reduce error budget burn.

## RAG status rules

Use these exact rules when asked for a RAG status:

- **Green** — all SLIs within target, no restart churn, memory headroom above 30%.
- **Amber** — any SLI breached in the last hour but recovered, **or** memory headroom below 30%,
  **or** any replica restart in the last 24 hours.
- **Red** — any SLI currently breached, **or** an open incident, **or** repeated restarts.

## Known baseline

Under normal workshop conditions the environment is idle: near-zero request volume and a flat error
rate. An idle environment is **Green**, not Amber — absence of traffic is not a fault. Say so explicitly
rather than reporting a misleading percentage computed from a handful of requests.

## Alerting

| Alert | Condition | Severity |
|---|---|---|
| `alert-http-5xx-sre-lab` | Requests with result code 5xx > 5 in 5 minutes | Sev3 |

Coverage gap to be aware of: there is currently **no latency alert and no memory-pressure alert**.
A memory leak is therefore only detected once it has already caused 5xx. Flag this in reliability
reviews until it is addressed.
