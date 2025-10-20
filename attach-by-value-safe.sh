#!/usr/bin/env bash
# -- self-load env + CURL_JSON (auto-refresh) --
[ -f "./.m2-env" ] && . "./.m2-env"
[ -f "./.m2-env.d/10-autorefresh.sh" ] && . "./.m2-env.d/10-autorefresh.sh"
type -t CURL_JSON >/dev/null || { echo "❌ CURL_JSON mangler – kjør: source ./.m2-env && source ./.m2-env.d/10-autorefresh.sh"; exit 1; }
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"
: "${PARENT_SKU:=TEST-CFG}"; : "${ATTR_CODE:=cfg_color}"
: "${NEW_SKU:?}"; : "${NEW_VAL_ID:?}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"

json_get() { curl -fsS -H "$AUTH_ADMIN" "$1"; }

# 0) Allerede koblet? -> ferdig
if json_get "$READ_BASE/configurable-products/$PARENT_SKU/children" \
   | jq -e --arg s "$NEW_SKU" 'map(.sku)==null or any(.sku==$s)' >/dev/null; then
  echo "✅ $NEW_SKU er allerede koblet til $PARENT_SKU"
  exit 0
fi

# 1) Finn alle andre children med samme verdi (NEW_VAL_ID) og detacher dem
for S in $(json_get "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -r '.[].sku'); do
  V=$(json_get "$READ_BASE/products/$S?fields=custom_attributes" \
      | jq -r --arg c "$ATTR_CODE" '.custom_attributes[]? | select(.attribute_code==$c) | .value')
  if [ "$V" = "$NEW_VAL_ID" ] && [ "$S" != "$NEW_SKU" ]; then
    echo "→ Detacher $S (value=$V)…"
    curl -fsS -X DELETE -H "$AUTH_ADMIN" \
      "$WRITE_BASE/configurable-products/$PARENT_SKU/children/$S" >/dev/null || true
  fi
done

# 2) Prøv å attache – “already attached” behandles som OK
echo "→ Attacher $NEW_SKU …"
resp=$(curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
        --data "{\"childSku\":\"$NEW_SKU\"}" \
        "$WRITE_BASE/configurable-products/$PARENT_SKU/child" || true)

if echo "$resp" | jq -e '.==true' >/dev/null 2>&1; then
  echo "✅ Attached."
elif echo "$resp" | jq -e '.message? | contains("already attached")' >/dev/null 2>&1; then
  echo "✅ Allerede attached."
else
  echo "⚠️  Uventet svar fra attach: $resp"
fi

# 3) Vis fasit
echo "→ Children nå:"
json_get "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'