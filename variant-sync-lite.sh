#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"
: "${PARENT_SKU:=TEST-CFG}"; : "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"; : "${SOURCE_CODE:=default}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"
CURL_OPTS="${CURL_OPTS:---connect-timeout 5 --max-time 20 --retry 2 --retry-delay 1 --fail}"

say(){ printf '%s\n' "$*"; }
sku_from(){ printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr ' ' '-' | tr -cd 'A-Z0-9-_'; }

say "== Variant Auto-Healer (lite) =="
say "BASE=$BASE  PARENT=$PARENT_SKU  ATTR=$ATTR_CODE  WEBSITE=$WEBSITE_ID"

# attribute + options
attr_json="$(curl -sS $CURL_OPTS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE")"
attr_id="$(printf '%s' "$attr_json" | jq -r '.attribute_id // empty')"
[ -n "$attr_id" ] || { echo "❌ Fant ikke attribute $ATTR_CODE"; exit 1; }

opts="$(curl -sS $CURL_OPTS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE/options" \
  | jq -c '[.[]? | select(.value!="" and .value!=null)
            | {value:(try (.value|tonumber) // empty), label}] // []')"

children="$(curl -sS $CURL_OPTS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" \
  | jq -r '.[]?.sku' || true)"
say "Current children:"
printf '%s\n' "${children:-}" | sed '/^$/d' || true

# For hver option: sørg for simple + stock + attach
printf '%s' "$opts" | jq -c '.[]' | while IFS= read -r row; do
  val="$(printf '%s' "$row" | jq -r '.value')"
  label="$(printf '%s' "$row" | jq -r '.label')"
  [ -n "$val" ] || continue
  sku="TEST-$(sku_from "$label")"
  name="TEST $label"
  if ! printf '%s\n' "$children" | grep -qx "$sku"; then
    body="$(jq -n --arg sku "$sku" --arg name "$name" --arg val "$val" --argjson wid "$WEBSITE_ID" \
      '{product:{sku:$sku,name:$name,type_id:"simple",attribute_set_id:4,visibility:1,price:399,status:1,weight:1,
                 extension_attributes:{website_ids:[$wid]},
                 custom_attributes:[{attribute_code:"'"$ATTR_CODE"'",value:$val}]}}')"
    curl -sS $CURL_OPTS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data-binary "$body" "$WRITE_BASE/products" >/dev/null || true

    qty="${DEFAULT_QTY:-5}"; case "$qty" in (*[!0-9.]*|"") qty=5;; esac
    stock="$(jq -n --arg sku "$sku" --argjson q "$qty" \
      '{sourceItems:[{sku:$sku,source_code:"'"$SOURCE_CODE"'",quantity:$q,status:1}]}' )"
    curl -sS $CURL_OPTS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data-binary "$stock" "$WRITE_BASE/inventory/source-items" >/dev/null || true

    curl -sS $CURL_OPTS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data "{\"childSku\":\"$sku\"}" "$WRITE_BASE/configurable-products/$PARENT_SKU/child" >/dev/null || true
    say "Attached: $sku ($label → $val)"
  fi
done

curl -sS $CURL_OPTS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
