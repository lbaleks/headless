#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"
: "${PARENT_SKU:=TEST-CFG}"; : "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"; : "${SOURCE_CODE:=default}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"

say(){ printf '%s\n' "$*"; }

say "== Variant Auto-Healer =="
say "BASE=$BASE  PARENT=$PARENT_SKU  ATTR=$ATTR_CODE  WEBSITE=$WEBSITE_ID"

# 1) hent attribute + options (alltid JSON)
attr_json="$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE")"
attr_id="$(printf '%s' "$attr_json" | jq -r '.attribute_id // empty')"
[ -n "$attr_id" ] || { echo "❌ Fant ikke attribute $ATTR_CODE"; exit 1; }

opts="$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE/options" \
  | jq -c '[.[]? | select(.value!="" and .value!=null)
            | {value:(try (.value|tonumber) // empty), label}] // []')"

# 2) current children
children="$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" \
  | jq -r '.[]?.sku' || true)"
say "Current children:"; printf '%s\n' "${children:-}" | sed '/^$/d' || true

# 3) ensure parent has option for this attribute with alle option values
want_vals="$(printf '%s' "$opts" | jq -c '[.[].value | select(.!=null)] // []')"

parent_json="$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes")"
parent_opt_id="$(printf '%s' "$parent_json" \
  | jq -r --arg id "$attr_id" '
      .extension_attributes.configurable_product_options // []
      | map(select(.attribute_id==$id)) | .[0].id // empty')"

if [ -z "${parent_opt_id:-}" ]; then
  data="$(jq -n --arg id "$attr_id" --arg label "$ATTR_CODE" --argjson vals "$want_vals" \
          '{option:{attribute_id:$id,label:$label,position:0,is_use_default:true,
                    values:($vals|map({value_index:.}))}}')"
  curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data-binary "$data" "$WRITE_BASE/configurable-products/$PARENT_SKU/options" >/dev/null
else
  have_vals="$(printf '%s' "$parent_json" \
    | jq -c --arg id "$attr_id" '
        .extension_attributes.configurable_product_options // []
        | map(select(.attribute_id==$id)) | .[0].values // [] | map(.value_index) // []')"
  merged="$(jq -c --argjson a "$have_vals" --argjson c "$want_vals" '($a + $c) | unique')"
  data="$(jq -n --arg id "$attr_id" --argjson vals "$merged" \
          '{option:{attribute_id:$id,label:"Config Color",position:0,is_use_default:true,
                    values:($vals|map({value_index:.}))}}')"
  curl -sS -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data-binary "$data" "$WRITE_BASE/configurable-products/$PARENT_SKU/options/$parent_opt_id" >/dev/null
fi

# 4) lag/attach children for alle options (idempotent)
printf '%s' "$opts" | jq -c '.[]' | while IFS= read -r row; do
  val="$(printf '%s' "$row" | jq -r '.value')"
  label="$(printf '%s' "$row" | jq -r '.label')"
  [ -n "$val" ] || continue

  # SKU basert på label
  sku="TEST-$(printf '%s' "$label" | tr '[:lower:]' '[:upper:]' | tr ' ' '-' | tr -cd 'A-Z0-9-_')"
  name="TEST $label"

  if ! printf '%s\n' "$children" | grep -qx "$sku"; then
    body="$(jq -n --arg sku "$sku" --arg name "$name" --arg val "$val" \
             --argjson wid "${WEBSITE_ID:-1}" \
      '{product:{sku:$sku,name:$name,type_id:"simple",attribute_set_id:4,visibility:1,price:399,status:1,weight:1,
                 extension_attributes:{website_ids:[$wid]},
                 custom_attributes:[{attribute_code:"'"$ATTR_CODE"'",value:$val}]}}')"
    curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data-binary "$body" "$WRITE_BASE/products" >/dev/null || true

    qty="${DEFAULT_QTY:-5}"
    case "$qty" in (*[!0-9.]*|"") qty=5;; esac
    stock="$(jq -n --arg sku "$sku" --argjson q "$qty" \
      '{sourceItems:[{sku:$sku,source_code:"'"$SOURCE_CODE"'",quantity:$q,status:1}]}' )"
    curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data-binary "$stock" "$WRITE_BASE/inventory/source-items" >/dev/null || true

    curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data "{\"childSku\":\"$sku\"}" "$WRITE_BASE/configurable-products/$PARENT_SKU/child" >/dev/null || true
    say "Attached: $sku ($label → $val)"
  fi
done

# 5) vis sluttstatus
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
