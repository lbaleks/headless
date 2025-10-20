#!/usr/bin/env bash
# Usage: tools/ibu-autoinstall.sh <SKU> <IBU>
set -eo pipefail

SKU="${1:-}"; IBU="${2:-}"
if [[ -z "$SKU" || -z "$IBU" ]]; then
  echo "Bruk: $0 <SKU> <IBU>"; exit 2
fi

# --- Load MAGENTO_* from .env.local safely (no substring ops) ---
if [[ -f ".env.local" ]]; then
  awk -F= '/^MAGENTO_/ && $2 {
    v=$0; sub(/^[^=]+=/,"",v);
    gsub(/\r/,"",v);                  # strip CR
    if (v ~ /^".*"$/) { sub(/^"/,"",v); sub(/"$/,"",v) }
    if (v ~ /^'\''.*'\''$/) { sub(/^'\''/,"",v); sub(/'\''$/,"",v) }
    printf("export %s=\"%s\"\n",$1,v)
  }' .env.local > /tmp/magento_env.sh
  # shellcheck disable=SC1091
  source /tmp/magento_env.sh
fi

BASE_RAW="${MAGENTO_URL:-${MAGENTO_BASE_URL:-}}"
if [[ -z "$BASE_RAW" ]]; then
  echo "❌ Sett MAGENTO_URL eller MAGENTO_BASE_URL i .env.local"; exit 1
fi
# Trim trailing slash without substr
case "$BASE_RAW" in
  */) BASE_RAW="${BASE_RAW%/}";;
esac
V1="${BASE_RAW}/V1"
echo "🔗 Magento V1: $V1"

ADMIN_USER="${MAGENTO_ADMIN_USERNAME:-}"
ADMIN_PASS="${MAGENTO_ADMIN_PASSWORD:-}"
if [[ -z "$ADMIN_USER" || -z "$ADMIN_PASS" ]]; then
  echo "❌ Sett MAGENTO_ADMIN_USERNAME og MAGENTO_ADMIN_PASSWORD i .env.local"; exit 1
fi

echo "🔐 Henter admin-token…"
ADMIN_JWT="$(curl -sS -X POST "$V1/integration/admin/token" \
  -H 'Content-Type: application/json' \
  --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
  | tr -d '"')"
if [[ -z "$ADMIN_JWT" || "$ADMIN_JWT" == *"message"* ]]; then
  echo "❌ Klarte ikke hente admin-token"; exit 1
fi
echo "✅ Admin-token klart"

jq_safe() { jq -r "$@" 2>/dev/null || true; }

echo "🛠  Sikrer attributt 'ibu'…"
ATTR_CODE="$(curl -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/attributes/ibu" | jq_safe '.attribute_code // empty')"
if [[ "$ATTR_CODE" != "ibu" ]]; then
  echo "   Attributt mangler – oppretter…"
  read -r -d '' CREATE_JSON <<'JSON' || true
{
  "attribute": {
    "attribute_code": "ibu",
    "frontend_input": "text",
    "backend_type": "varchar",
    "is_required": false,
    "is_unique": false,
    "is_user_defined": true,
    "is_visible": true,
    "is_comparable": false,
    "is_searchable": false,
    "is_configurable": false,
    "is_visible_on_front": true,
    "is_html_allowed_on_front": false,
    "is_filterable": false,
    "is_filterable_in_search": false,
    "is_visible_in_advanced_search": false,
    "used_for_sort_by": false,
    "is_used_for_promo_rules": false,
    "frontend_labels": [{"store_id":0,"label":"IBU"}]
  }
}
JSON
  curl -sS -X POST "$V1/products/attributes" \
    -H "Authorization: Bearer $ADMIN_JWT" \
    -H 'Content-Type: application/json' \
    --data "$CREATE_JSON" >/dev/null

  ATTR_CODE="$(curl -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/attributes/ibu" | jq_safe '.attribute_code // empty')"
  if [[ "$ATTR_CODE" != "ibu" ]]; then
    echo "❌ Klarte ikke opprette attributt 'ibu'"; exit 1
  fi
fi
echo "✓ Attributt 'ibu' finnes"

echo "🔎 Henter attribute_set_id for $SKU…"
SET_ID="$(curl -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/$SKU" | jq_safe '.attribute_set_id')"
if [[ -z "$SET_ID" || "$SET_ID" == "null" ]]; then
  echo "❌ Fant ikke attribute_set_id for $SKU"; exit 1
fi
echo "   attribute_set_id=$SET_ID"

echo "🔎 Henter attribute_group_id (General)…"
GROUPS="$(
  curl -g -sS --get -H "Authorization: Bearer $ADMIN_JWT" \
    --data-urlencode "searchCriteria[filterGroups][0][filters][0][field]=attribute_set_id" \
    --data-urlencode "searchCriteria[filterGroups][0][filters][0][value]=$SET_ID" \
    --data-urlencode "searchCriteria[filterGroups][0][filters][0][condition_type]=eq" \
    --data-urlencode "searchCriteria[pageSize]=200" \
    "$V1/products/attribute-sets/groups/list"
)"

# Robust jq: number/array/object
GROUP_ID="$(printf '%s' "$GROUPS" | jq_safe '
  if type=="number" then tostring
  elif type=="array" then
    (map(select((.attribute_group_name|tostring|ascii_downcase)=="general"))[0].attribute_group_id
      // .[0].attribute_group_id // empty) | tostring
  elif type=="object" and (.items|type)=="array" then
    (
      (.items | map(select((.attribute_group_name|tostring|ascii_downcase)=="general"))[0].attribute_group_id)
      // (.items[0].attribute_group_id) // empty
    ) | tostring
  else empty end
')"

if [[ -z "$GROUP_ID" || "$GROUP_ID" == "null" ]]; then
  echo "⚠️  Uventet respons fra groups/list, prøver enkel fallback…"
  GROUP_ID="$(printf '%s' "$GROUPS" | tr -cd '0-9\n' | awk 'NF{print;exit}')"
fi
if [[ -z "$GROUP_ID" ]]; then
  echo "❌ Fant ikke attribute_group_id for set=$SET_ID"; exit 1
fi
echo "   attribute_group_id=$GROUP_ID"

echo "🔗 Tilordner 'ibu' til set=$SET_ID group=$GROUP_ID (idempotent)…"
ASSIGN_MSG="$(
  curl -sS -X POST "$V1/products/attribute-sets/attributes" \
    -H "Authorization: Bearer $ADMIN_JWT" \
    -H 'Content-Type: application/json' \
    --data "{\"attributeSetId\":$SET_ID,\"attributeGroupId\":$GROUP_ID,\"attributeCode\":\"ibu\",\"sortOrder\":10}"
)"
MSG="$(printf '%s' "$ASSIGN_MSG" | jq_safe '.message // empty')"
[[ -n "$MSG" ]] && echo "ℹ️  $MSG" || echo "OK or already assigned"

echo "✍️  Oppdaterer $SKU.ibu=$IBU…"
PUT_RES="$(
  curl -sS -X PUT "$V1/products/$SKU" \
    -H "Authorization: Bearer $ADMIN_JWT" \
    -H 'Content-Type: application/json' \
    --data '{"product":{"sku":"'"$SKU"'","custom_attributes":[{"attribute_code":"ibu","value":"'"$IBU"'"}]}}'
)"
# Ikke feile hvis Magento returnerer en streng – vi verifiserer under
echo "$PUT_RES" >/dev/null

echo "🔎 Verifiserer i Magento…"
curl -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/$SKU" \
 | jq -r '.custom_attributes[]? | select(.attribute_code=="ibu") // empty'
echo "🎉 Ferdig."
