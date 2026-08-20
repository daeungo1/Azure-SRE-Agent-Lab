#!/bin/bash
# =============================================================================
# Scenario 1-C — Capacity starvation (slow responses, no errors)
#
# Ground truth: CPU is cut to a quarter and scale-out is disabled, so the app
# keeps answering 200 but takes far longer. Nothing crashes and nothing returns
# 5xx — the agent has to recognise a capacity problem instead of reaching for
# the OOM or config-error explanations it has seen before.
#
#   ./scripts/break-app-latency.sh break     # inject
#   ./scripts/break-app-latency.sh load      # drive concurrent traffic
#   ./scripts/break-app-latency.sh restore   # roll back
#   ./scripts/break-app-latency.sh status    # show sizing and a timed request
# =============================================================================
set -euo pipefail

RG="${RG:-rg-sre-lab}"
APP="${APP:-}"
# Container Apps only allows fixed CPU:memory pairs (1:2 ratio).
GOOD_CPU="1.0";  GOOD_MEM="2Gi";  GOOD_MAX="5"
BAD_CPU="0.25";  BAD_MEM="0.5Gi"; BAD_MAX="1"
CONCURRENCY="${CONCURRENCY:-8}"
ROUNDS="${ROUNDS:-40}"

if [ -z "$APP" ]; then
  APP=$(az containerapp list -g "$RG" --query "[?starts_with(name,'ca-grubify-') && !contains(name,'-fe-')].name | [0]" -o tsv)
fi
if [ -z "$APP" ]; then
  echo "Error: could not find the Grubify API container app in resource group $RG." >&2
  exit 1
fi

FQDN=$(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)
URL="https://$FQDN/api/fooditems"

show_status() {
  echo ""
  echo "  App:  $APP"
  az containerapp show -g "$RG" -n "$APP" --query \
    "{cpu:properties.template.containers[0].resources.cpu, memory:properties.template.containers[0].resources.memory, minReplicas:properties.template.scale.minReplicas, maxReplicas:properties.template.scale.maxReplicas}" -o table
  printf "  timed request: "
  curl -s -m 60 -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" "$URL" || echo "failed"
  echo ""
}

drive_load() {
  echo "  Driving $CONCURRENCY concurrent streams x $ROUNDS rounds against $URL"
  echo "  start $(date -u +%H:%M:%SZ)"
  for _ in $(seq 1 "$ROUNDS"); do
    for _ in $(seq 1 "$CONCURRENCY"); do
      curl -s -m 60 -o /dev/null "$URL" &
    done
    wait
  done
  echo "  end   $(date -u +%H:%M:%SZ)"
}

case "${1:-status}" in
  break)
    echo ""
    echo "============================================="
    echo "  Scenario 1-C — starving the app of CPU"
    echo "============================================="
    echo ""
    echo "  Before: cpu=$GOOD_CPU mem=$GOOD_MEM maxReplicas=$GOOD_MAX"
    echo "  After:  cpu=$BAD_CPU mem=$BAD_MEM maxReplicas=$BAD_MAX (no scale-out to hide it)"
    echo ""
    echo "  Injecting at $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC ..."
    az containerapp update -g "$RG" -n "$APP" \
      --cpu "$BAD_CPU" --memory "$BAD_MEM" --min-replicas 1 --max-replicas "$BAD_MAX" -o none
    echo "  Done. Responses should stay 200 but get much slower."
    show_status
    ;;
  load)
    drive_load
    ;;
  restore)
    echo ""
    echo "  Restoring cpu=$GOOD_CPU mem=$GOOD_MEM maxReplicas=$GOOD_MAX at $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC ..."
    az containerapp update -g "$RG" -n "$APP" \
      --cpu "$GOOD_CPU" --memory "$GOOD_MEM" --min-replicas 1 --max-replicas "$GOOD_MAX" -o none
    echo "  Done."
    show_status
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage: $0 [break|load|restore|status]" >&2
    exit 1
    ;;
esac
