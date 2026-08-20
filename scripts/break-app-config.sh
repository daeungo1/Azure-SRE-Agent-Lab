#!/bin/bash
# =============================================================================
# Scenario 1-B — Bad deployment config (ingress port mismatch)
#
# Ground truth: the ingress is pointed at a container port nothing listens on,
# so every request fails at the edge while the container itself stays healthy.
# Same symptom as scenario 1 (HTTP 5xx) but a completely different root cause,
# which is exactly what the agent has to tell apart.
#
# Note: changing ASPNETCORE_URLS alone does NOT break this image — it binds 8080
# regardless. Moving the ingress target is what reliably produces the outage.
#
#   ./scripts/break-app-config.sh break     # inject
#   ./scripts/break-app-config.sh restore   # roll back
#   ./scripts/break-app-config.sh status    # show config and health
# =============================================================================
set -euo pipefail

RG="${RG:-rg-sre-lab}"
APP="${APP:-}"
GOOD_PORT="8080"
BAD_PORT="9090"

if [ -z "$APP" ]; then
  APP=$(az containerapp list -g "$RG" --query "[?starts_with(name,'ca-grubify-') && !contains(name,'-fe-')].name | [0]" -o tsv)
fi

if [ -z "$APP" ]; then
  echo "Error: could not find the Grubify API container app in resource group $RG." >&2
  exit 1
fi

FQDN=$(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)

show_status() {
  echo ""
  echo "  App:          $APP"
  echo "  URL:          https://$FQDN"
  printf "  targetPort:   "
  az containerapp ingress show -g "$RG" -n "$APP" --query targetPort -o tsv
  printf "  GET /api/fooditems -> HTTP "
  curl -s -m 20 -o /dev/null -w "%{http_code}\n" "https://$FQDN/api/fooditems" || echo "000"
  echo ""
}

case "${1:-status}" in
  break)
    echo ""
    echo "============================================="
    echo "  Scenario 1-B — pointing ingress at a dead port"
    echo "============================================="
    echo ""
    echo "  Before: ingress targetPort=$GOOD_PORT (app listens here)"
    echo "  After:  ingress targetPort=$BAD_PORT (nothing listens here)"
    echo ""
    echo "  Injecting at $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC ..."
    az containerapp ingress update -g "$RG" -n "$APP" --target-port "$BAD_PORT" -o none
    echo "  Done. Every request should now fail at the ingress."
    show_status
    ;;
  restore)
    echo ""
    echo "  Restoring ingress targetPort=$GOOD_PORT at $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC ..."
    az containerapp ingress update -g "$RG" -n "$APP" --target-port "$GOOD_PORT" -o none
    echo "  Done."
    show_status
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage: $0 [break|restore|status]" >&2
    exit 1
    ;;
esac
