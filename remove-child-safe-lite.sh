#!/usr/bin/env bash
# -- self-load env + CURL_JSON (auto-refresh) --
[ -f "./.m2-env" ] && . "./.m2-env"
[ -f "./.m2-env.d/10-autorefresh.sh" ] && . "./.m2-env.d/10-autorefresh.sh"
type -t CURL_JSON >/dev/null || { echo "❌ CURL_JSON mangler – kjør: source ./.m2-env && source ./.m2-env.d/10-autorefresh.sh"; exit 1; }
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"
: "${PARENT_SKU:=TEST-CFG}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"

child="${1:?Bruk: ./remove-child-safe-lite.sh <CHILD_SKU>}"

# Sjekk om child er linket
linked=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" \
  | jq -r --arg s "$child" 'map(.sku) | index($s) | not | not')

if [ "$linked" != "true" ]; then
  echo "⚠️  $child er ikke linket – hopper over."
  curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
  exit 0
fi

# Detach via auto-refresh wrapper
CURL_JSON DELETE "$WRITE_BASE/configurable-products/$PARENT_SKU/children/$child" | jq .

# Vis status
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
