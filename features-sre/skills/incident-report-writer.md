# Incident Report Writer

Produce a report someone who was asleep during the incident can read once and fully understand.

## Rules

- **Every section is mandatory.** If a section has no content, write why — never leave it blank.
- **All timestamps in UTC**, ISO-8601, and always paired with what happened at that instant.
- **Evidence must be reproducible.** Paste the actual KQL or CLI command, not a description of it.
- **Separate fact from inference.** Mark anything not directly observed as `Hypothesis:`.
- **No blame.** Name systems and changes, not people.

## Template

### Summary
Two sentences: what broke, and what the user-visible effect was.

### Impact
- Affected service and endpoints
- Duration (start → mitigated → resolved, UTC)
- Failed request count and error rate at peak
- Customer-visible symptom

### Timeline
| Time (UTC) | Event | Source |
|---|---|---|

Include at minimum: first error, alert fired, investigation started, root cause identified,
remediation applied, service verified healthy, alert closed.

### Evidence
For each claim, one subsection with the query and a one-line reading of the result.

### Root Cause
A single causal chain, ending at the change or condition that started it. If the true root cause is not
yet proven, say so explicitly and list what evidence would confirm it.

### Remediation
- What was done, by whom or by which agent, at what time
- Whether it was a mitigation (restores service) or a fix (removes the cause)

### Action Items
| # | Action | Owner | Priority | Prevents recurrence? |
|---|---|---|---|---|

At least one item must address prevention, not just detection.

### References
Full ARM resource IDs, Log Analytics workspace ID, Application Insights resource ID, revision names,
alert rule name, and links to any related issues.

## Before submitting

Re-read the report and confirm: could a reader reproduce the diagnosis from this document alone?
If not, the Evidence section is incomplete.
