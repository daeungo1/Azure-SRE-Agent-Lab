# Container App Safe Scaling

Apply resource or replica changes to an Azure Container App without creating a second incident.

## Guardrails

- **Read before you write.** Always fetch the current template first; never assume the current values.
- **Respect the CPU-to-memory ratio.** Azure Container Apps (Consumption) accepts only fixed pairs.
  A mismatched pair is rejected and leaves the app on the old revision.

  | CPU | Memory |
  |----:|-------:|
  | 0.25 | 0.5Gi |
  | 0.5  | 1.0Gi |
  | 0.75 | 1.5Gi |
  | 1.0  | 2.0Gi |
  | 1.25 | 2.5Gi |
  | 1.5  | 3.0Gi |
  | 1.75 | 3.5Gi |
  | 2.0  | 4.0Gi |

- **One change at a time.** Do not resize and change replica bounds in the same operation — you lose the
  ability to attribute the outcome.
- **Never scale `minReplicas` to 0** on a service that is currently serving an incident; cold start will
  extend the outage.

## Procedure

1. Read the current state.

   ```bash
   az containerapp show -g <rg> -n <app> \
     --query "{cpu:properties.template.containers[0].resources.cpu, memory:properties.template.containers[0].resources.memory, scale:properties.template.scale}"
   ```

2. Apply the change. Resizing creates a new revision automatically.

   ```bash
   az containerapp update -g <rg> -n <app> --cpu 1.0 --memory 2.0Gi
   ```

3. Wait for the new revision and confirm it is healthy.

   ```bash
   az containerapp revision list -g <rg> -n <app> \
     --query "[?properties.active].{rev:name, health:properties.healthState, state:properties.runningState}" -o table
   ```

4. Verify with a real request against a previously failing endpoint. A `Healthy` revision that still
   returns 5xx means the change did not address the root cause.

## Rollback

If the new revision is unhealthy, shift traffic back to the last known-good revision rather than
editing the template again under pressure:

```bash
az containerapp ingress traffic set -g <rg> -n <app> --revision-weight <last-good-revision>=100
```

## Reporting

Record the before and after values, the old and new revision names, and the verification result.
