#!/usr/bin/env bash
set -euo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8
clean(){ perl -CSDA -pe 's/\r//g; s/\x{FEFF}//g; s/\p{Cf}//g; s/^\s+|\s+$//g'; }

SKU="$(printf '%s' "${1:-}" | clean)"
IBU_VAL="$(printf '%s' "${2:-}" | clean)"
[ -n "$SKU" ] || { echo "Usage: $0 <SKU> <IBU>"; exit 2; }
[ -n "$IBU_VAL" ] || { echo "Usage: $0 <SKU> <IBU>"; exit 2; }

BASE="${MAGENTO_URL:-${MAGENTO_BASE_URL:-}}"
[ -n "$BASE" ] || { echo "❌ Sett MAGENTO_URL eller MAGENTO_BASE_URL i .env.local"; exit 1; }
V1="${BASE%/}/V1"

# admin token
if [ -z "${MAGENTO_ADMIN_USERNAME:-}" ] || [ -z "${MAGENTO_ADMIN_PASSWORD:-}" ]; then
  echo "❌ Mangler MAGENTO_ADMIN_USERNAME/MAGENTO_ADMIN_PASSWORD"; exit 1;
fi
ADMIN_JWT="$(curl -g -sS -X POST "$V1/integration/admin/token" -H 'Content-Type: application/json' \
  --data '{"username":"'"$MAGENTO_ADMIN_USERNAME"'","password":"'"$MAGENTO_ADMIN_PASSWORD"'"}' | tr -d '"')"

echo "🔎 Sjekker/oppretter attributt 'ibu'…"
CREATE_RES="$(
  curl -g -sS -X POST "$V1/products/attributes" \
    -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
    --data @- <<JSON
{ "attribute": {
    "attribute_code":"ibu","frontend_input":"text","is_required":false,
    "is_user_defined":true,"default_frontend_label":"IBU","is_unique":false,
    "is_global":1
} }
JSON
)"
# Ignorer “already exists”
echo "$CREATE_RES" | jq -e 'if type=="object" and (.attribute_id? or .message?) then . else empty end' >/dev/null 2>&1 || true
echo "✓ Attributt ok"

SET_ID="$(curl -g -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/$SKU" | jq -r '.attribute_set_id')"
[ -n "$SET_ID" ] && [ "$SET_ID" != "null" ] || { echo "❌ Fant ikke attribute_set_id for $SKU"; exit 1; }

GROUPS="$(curl -g -sS -H "Authorization: Bearer $ADMIN_JWT" \
  "$V1/products/attribute-sets/groups/list?searchCriteria[filterGroups][0][filters][0][field]=attribute_set_id&searchCriteria[filterGroups][0][filters][0][value]=$SET_ID&searchCriteria[filterGroups][0][filters][0][condition_type]=eq&searchCriteria[pageSize]=200")"

GROUP_ID="$(
  echo "$GROUPS" | jq -r '
    if type=="number" then tostring
    elif type=="array" then
      (map(select((.attribute_group_name|tostring|ascii_downcase)=="general"))[0].attribute_group_id
       // .[0].attribute_group_id // empty)
    elif type=="object" then
      ((.items // []) as $a |
       ([$a[]? | select((.attribute_group_name|tostring|ascii_downcase)=="general")][0].attribute_group_id)
       // ($a[0]?.attribute_group_id) // empty)
    else empty end' | head -n1
)"
[ -n "$GROUP_ID" ] || { echo "❌ Fant ikke attribute_group_id for set=$SET_ID"; exit 1; }

# assign ibu to set/group (idempotent)
curl -g -sS -X POST "$V1/products/attribute-sets/attributes" \
  -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
  --data "{\"attributeSetId\":$SET_ID,\"attributeGroupId\":$GROUP_ID,\"attributeCode\":\"ibu\",\"sortOrder\":10}" \
| jq -r '.message? // "OK or already assigned"' >/dev/null 2>&1 || true

# update product
curl -g -sS -X PUT "$V1/products/$SKU" \
  -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
  --data "{\"product\":{\"sku\":\"$SKU\",\"custom_attributes\":[{\"attribute_code\":\"ibu\",\"value\":\"$IBU_VAL\"}]}}" >/dev/null

# verify
curl -g -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/$SKU" \
  | jq '.custom_attributes[]? | select(.attribute_code=="ibu")'
