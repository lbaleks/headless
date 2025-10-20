#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"; : "${PARENT_SKU:=TEST-CFG}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"
SKU="${1:-}"; [ -n "$SKU" ] || { echo "Bruk: $0 <child_sku>"; exit 1; }

# Bare fjern hvis den faktisk er linket
if curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" \
   | jq -e --arg s "$SKU" '[.[].sku] | index($s) != null' >/dev/null; then
  curl -sS -X DELETE -H "$AUTH_ADMIN" \
    "$WRITE_BASE/configurable-products/$PARENT_SKU/children/$SKU" | jq .
else
  echo "⚠️  $SKU er ikke linket – hopper over."
fi

# Vis resultat
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
