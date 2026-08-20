#!/bin/bash
# =============================================================================
# Scenario S3 — Slow responses, no errors
#
# Ground truth: ORDER_DELAY_MS makes the order endpoints answer slowly while
# still returning 200. Nothing crashes and nothing returns 5xx, so the agent has
# to reason about latency instead of reaching for the OOM or config-error
# explanations it has already seen.
#
# Requires the fork's ORDER_DELAY_MS middleware (GrubifyApi/Program.cs).
#
#   ./scripts/break-app-latency.sh break     # inject
#   ./scripts/break-app-latency.sh load      # drive concurrent traffic
#   ./scripts/break-app-latency.sh restore   # roll back
#   ./scripts/break-app-latency.sh status    # show setting and a timed request
# =============================================================================
set -euo pipefail

RG="${RG:-rg-sre-lab}"
APP="${APP:-}"
DELAY_MS="${DELAY_MS:-4000}"
CONCURRENCY="${CONCURRENCY:-8}"
ROUNDS="${ROUNDS:-12}"

if [ -z "$APP" ]; then
  APP=$(az containerapp list -g "$RG" --query "[?starts_with(name,'ca-grubify-') && !contains(name,'-fe-')].name | [0]" -o tsv)
fi
if [ -z "$APP" ]; then
  echo "Error: could not find the Grubify API container app in resource group $RG." >&2
  exit 1
fi

FQDN=$(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)
URL="https://$FQDN/api/orders/user/demo-user"

show_status() {
  echo ""
  echo "  App:  $APP"
  printf "  ORDER_DELAY_MS: "
  az containerapp show -g "$RG" -n "$APP" \
    --query "properties.template.containers[0].env[?name=='ORDER_DELAY_MS'].value | [0]" -o tsv
  printf "  timed request:  "
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
    echo "  Scenario S3 — delaying the order endpoints"
    echo "============================================="
    echo ""
    echo "  Setting ORDER_DELAY_MS=$DELAY_MS (responses stay 200, just slow)"
    echo "  Injecting at $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC ..."
    az containerapp update -g "$RG" -n "$APP" \
      --set-env-vars "ORDER_DELAY_MS=$DELAY_MS" -o none
    echo "  Done. Wait for the new revision to go healthy before driving load."
    show_status
    ;;
  load)
    drive_load
    ;;
  restore)
    echo ""
    echo "  Restoring ORDER_DELAY_MS=0 at $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC ..."
    az containerapp update -g "$RG" -n "$APP" \
      --set-env-vars "ORDER_DELAY_MS=0" -o none
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
