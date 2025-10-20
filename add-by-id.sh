#!/usr/bin/env bash
set -euo pipefail

: "${BASE:?}"; : "${AUTH_ADMIN:?}"
: "${PARENT_SKU:=TEST-CFG}"; : "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"; : "${SOURCE_CODE:=default}"
: "${NEW_VAL_ID:?Need NEW_VAL_ID}"; : "${NEW_LABEL:?Need NEW_LABEL}"; : "${NEW_SKU:?Need NEW_SKU}"

READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"
# Hard timeouts + kill 100-continue stalls
CURL_OPTS=${CURL_OPTS:-"--fail --show-error --silent --connect-timeout 5 --max-time 25 --retry 1 --retry-delay 1"}
CURL_JSON(){ curl $CURL_OPTS -H "$AUTH_ADMIN" -H 'Content-Type: application/json' -H 'Expect:' --write-out "\nHTTP:%{http_code}\n" "$@"; }
# Sikre mengde selv om set -u er på
qty="${NEW_QTY:-5}"

echo "→ Ensure simple ${NEW_SKU} (value=${NEW_VAL_ID})…"

# 1) Opprett / idempotent simple
body="$(jq -n \
  --arg sku "$NEW_SKU" \
  --arg name "TEST ${NEW_LABEL}" \
  --argjson val "$NEW_VAL_ID" \
  --argjson wid "$WEBSITE_ID" \
  '{product:{
    sku:$sku,name:$name,type_id:"simple",attribute_set_id:4,visibility:1,price:399,status:1,weight:1,
    extension_attributes:{website_ids:[$wid]},
    custom_attributes:[{attribute_code:"'"$ATTR_CODE"'",value:$val}]
  }}')"
curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data-binary "$body" "$WRITE_BASE/products" >/dev/null || true

# 2) Lager / MSI
stock="$(jq -n \
  --arg sku "$NEW_SKU" \
  --arg src "$SOURCE_CODE" \
  --argjson q "$qty" \
  '{sourceItems:[{sku:$sku,source_code:$src,quantity:$q,status:1}]}' )"
curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data-binary "$stock" "$WRITE_BASE/inventory/source-items" >/dev/null || true

# 3) Sørg for at parent-option inkluderer verdien
attr_id="$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE" | jq -r '.attribute_id')"
real_id="$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes" \
  | jq -r --arg id "$attr_id" '
      .extension_attributes.configurable_product_options // []
      | map(select(.attribute_id==$id)) | .[0].id // empty')"

if [ -n "${real_id:-}" ]; then
  have="$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes" \
    | jq -c --arg id "$attr_id" '
        .extension_attributes.configurable_product_options // []
        | map(select(.attribute_id==$id)) | .[0].values // [] | map(.value_index) // []')"
  merged="$(jq -c --argjson a "$have" --argjson c "[$NEW_VAL_ID]" '($a + $c) | unique')"
  data="$(jq -n --arg id "$attr_id" --argjson vals "$merged" \
     '{option:{attribute_id:$id,label:"Config Color",position:0,is_use_default:true,values:($vals|map({value_index:.}))}}')"
  curl -sS -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data-binary "$data" "$WRITE_BASE/configurable-products/$PARENT_SKU/options/$real_id" >/dev/null
fi

# 4) Knytt som child (idempotent)
curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data "{\"childSku\":\"$NEW_SKU\"}" \
  "$WRITE_BASE/configurable-products/$PARENT_SKU/child" >/dev/null || true

# 5) Vis resultat
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
