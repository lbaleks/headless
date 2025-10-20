#!/usr/bin/env bash
set -euo pipefail
source ./.m2-env
source ./.m2-lib.sh
: "${PARENT_SKU:=TEST-CFG}"
: "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"
: "${SOURCE_CODE:=default}"

NEW_LABEL="${NEW_LABEL:-}"
NEW_VAL_ID="${NEW_VAL_ID:-}"
NEW_SKU="${NEW_SKU:-}"
NEW_QTY="${NEW_QTY:-5}"
[ -z "$NEW_SKU" ] && { echo "NEW_SKU er påkrevd"; exit 1; }

# 1) Finn attr id
CFG_ATTR_ID=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE" | jq -r '.attribute_id')
[ -z "$CFG_ATTR_ID" ] || [ "$CFG_ATTR_ID" = "null" ] && { echo "Fant ikke attribute $ATTR_CODE"; exit 1; }

# 2) Finn/lag option verdi
VAL_ID="$NEW_VAL_ID"
if [ -z "$VAL_ID" ]; then
  if [ -n "$NEW_LABEL" ]; then
    # Prøv å opprette (kan feile på ACL)
    set +e
    CREATED=$(do_write POST "$WRITE_BASE/products/attributes/$ATTR_CODE/options" \
      "$(jq -c --arg l "$NEW_LABEL" '{option:{label:$l,sort_order:99,is_default:false}}')")
    ok=$?
    set -e
    if [ $ok -eq 0 ]; then
      VAL_ID=$(echo "$CREATED" | jq -r '. // empty')
    fi
  fi
  # Lookup uansett (case-insensitive)
  OPTS=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE/options")
  if [ -z "${VAL_ID:-}" ] || [ "$VAL_ID" = "null" ]; then
    VAL_ID=$(jq -r --arg l "${NEW_LABEL:-}" '
      map(select(.value != "")) |
      ( .[] | select((.label|ascii_downcase) == ($l|ascii_downcase)) | .value ) // empty
    ' <<<"$OPTS")
  fi
fi
[ -z "${VAL_ID:-}" ] && { echo "❌ Fant ikke/kunne ikke opprette option for label \"$NEW_LABEL\""; exit 1; }

# 3) Lag/fiks simple
PAYLOAD=$(jq -c --arg sku "$NEW_SKU" --argjson set 4 --argjson wid "$WEBSITE_ID" --arg val "$VAL_ID" '
  { product:{
      sku:$sku, name:$sku, type_id:"simple",
      attribute_set_id:$set, visibility:1, price:399, status:1, weight:1,
      extension_attributes:{ website_ids:[$wid] },
      custom_attributes:[ {attribute_code:"'${ATTR_CODE}'", value:$val} ]
    } }')
set +e
RES=$(do_write POST "$WRITE_BASE/products" "$PAYLOAD")
ok=$?; set -e
if [ $ok -ne 0 ]; then
  # Prøv PUT (eksisterer fra før)
  RES=$(do_write PUT "$WRITE_BASE/products/$NEW_SKU" "$PAYLOAD")
fi

# 3b) MSI
do_write POST "$WRITE_BASE/inventory/source-items" \
  "$(jq -c --arg sku "$NEW_SKU" --arg src "$SOURCE_CODE" --argjson qty "$NEW_QTY" \
     '{sourceItems:[{sku:$sku,source_code:$src,quantity:$qty,status:1}]}' )" >/dev/null || true

# 4) Sørg for at parent har option for attribute + verdi
PARENT=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes")
OPT_ID=$(jq -r --arg id "$CFG_ATTR_ID" '.extension_attributes.configurable_product_options[]? | select(.attribute_id==$id) | .id' <<<"$PARENT")
if [ -z "$OPT_ID" ]; then
  # Opprett option
  do_write POST "$WRITE_BASE/configurable-products/$PARENT_SKU/options" \
    "$(jq -c --arg id "$CFG_ATTR_ID" --arg l "$ATTR_CODE" --argjson vi "$VAL_ID" \
      '{option:{attribute_id:$id,label:$l,position:0,is_use_default:true,values:[{value_index:$vi}]}}' )" >/dev/null
else
  # Oppdater values (legg til hvis mangler)
  CURR=$(jq -c --arg id "$CFG_ATTR_ID" '
    .extension_attributes.configurable_product_options[] |
    select(.attribute_id==$id) | .values | map(.value_index)
  ' <<<"$PARENT")
  ADD=$(jq -r --argjson vi "$VAL_ID" --argjson arr "$CURR" '([ $vi ] - $arr) | length' <<<"{}")
  if [ "$ADD" != "0" ]; then
    NEWVALS=$(jq -c --argjson vi "$VAL_ID" --argjson arr "$CURR" \
      '($arr + [ $vi ]) | unique | map({value_index:.})' <<<"{}")
    do_write PUT "$WRITE_BASE/configurable-products/$PARENT_SKU/options/$OPT_ID" \
      "$(jq -c --argjson oid "$OPT_ID" --arg id "$CFG_ATTR_ID" --arg l "$ATTR_CODE" --argjson vals "$NEWVALS" \
        '{option:{id:$oid,attribute_id:$id,label:$l,position:0,is_use_default:true,values:$vals}}' )" >/dev/null
  fi
fi

# 5) Attach child
do_write POST "$WRITE_BASE/configurable-products/$PARENT_SKU/child" \
  "$(jq -c --arg sku "$NEW_SKU" '{childSku:$sku}')" >/dev/null || true

# 6) Vis status
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
