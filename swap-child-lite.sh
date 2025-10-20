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

old="${1:?Bruk: ./swap-child-lite.sh <OLD_SKU> <NEW_SKU>}"
new="${2:?Bruk: ./swap-child-lite.sh <OLD_SKU> <NEW_SKU>}"

echo "→ Detacher $old …"
CURL_JSON DELETE "$WRITE_BASE/configurable-products/$PARENT_SKU/children/$old" | jq . || true

echo "→ Attacher  $new …"
CURL_JSON POST "$WRITE_BASE/configurable-products/$PARENT_SKU/child" \
  --data "{\"childSku\":\"$new\"}" | jq .

echo "→ Verifiser:"
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
