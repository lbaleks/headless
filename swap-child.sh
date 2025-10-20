#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"
: "${PARENT_SKU:=TEST-CFG}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"

OLD="${1:-}"; NEW="${2:-}"
if [ -z "$OLD" ] || [ -z "$NEW" ]; then
  echo "Bruk: ./swap-child.sh <old_sku> <new_sku>"; exit 1
fi

echo "→ Detacher $OLD …"
curl -sS -X DELETE -H "$AUTH_ADMIN" \
  "$WRITE_BASE/configurable-products/$PARENT_SKU/children/$OLD" | jq .

echo "→ Attacher  $NEW …"
curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data "{\"childSku\":\"$NEW\"}" \
  "$WRITE_BASE/configurable-products/$PARENT_SKU/child" | jq .

echo "→ Verifiser:"
curl -sS -H "$AUTH_ADMIN" \
  "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
