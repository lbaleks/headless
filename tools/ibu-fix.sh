#!/usr/bin/env bash
set -euo pipefail

# --- INN: parametre ---
SKU="${1:-TEST-RED}"
IBU="${2:-37}"

# --- Miljø ---
# Prøv å laste miljø hvis ikke allerede satt i sesjonen
if [ -z "${MAGENTO_URL:-${MAGENTO_BASE_URL:-}}" ] || { [ -z "${MAGENTO_ADMIN_USERNAME:-}" ] && [ -z "${MAGENTO_TOKEN:-}" ]; }; then
  if [ -x tools/load-magento-env.sh ]; then
    # shellcheck disable=SC1091
    source tools/load-magento-env.sh
  fi
fi

BASE_RAW="${MAGENTO_URL:-${MAGENTO_BASE_URL:-}}"
if [ -z "$BASE_RAW" ]; then
  echo "❌ MAGENTO_URL/MAGENTO_BASE_URL mangler (i miljø eller .env.local)"; exit 1
fi
V1="${BASE_RAW%/}/V1"

echo "🔧 IBU-fix for SKU=$SKU → $IBU"
echo "🔗 Magento V1: $V1"

# --- Tokenhenting: bruk MAGENTO_TOKEN hvis satt; ellers admin-login ---
if [ -n "${MAGENTO_TOKEN:-}" ]; then
  ADMIN_JWT="$MAGENTO_TOKEN"
  echo "ℹ️  Bruker forhåndsdefinert MAGENTO_TOKEN"
else
  if [ -z "${MAGENTO_ADMIN_USERNAME:-}" ] || [ -z "${MAGENTO_ADMIN_PASSWORD:-}" ]; then
    echo "❌ Verken MAGENTO_TOKEN eller admin-cred (MAGENTO_ADMIN_USERNAME/MAGENTO_ADMIN_PASSWORD) er satt"; exit 1
  fi
  echo "🔐 Henter admin-token…"
  ADMIN_JWT="$(curl -sS -X POST "$V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data '{"username":"'"${MAGENTO_ADMIN_USERNAME}"'","password":"'"${MAGENTO_ADMIN_PASSWORD}"'"}' | tr -d '"')"
  if [ -z "$ADMIN_JWT" ] || [[ "$ADMIN_JWT" == *"message"* ]]; then
    echo "❌ Admin token feilet: $ADMIN_JWT"; exit 1
  fi
  echo "✅ Admin-token klart"
fi

# --- Finn attribute_set_id ---
SET_ID="$(curl -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/$SKU" | jq -r '.attribute_set_id')"
if ! [[ "$SET_ID" =~ ^[0-9]+$ ]]; then
  echo "❌ Klarte ikke å hente attribute_set_id for $SKU (fikk: $SET_ID)"; exit 1
fi
echo "🔎 attribute_set_id=$SET_ID"

# --- Sørg for at 'ibu' er i attribute set ---
if curl -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/attribute-sets/$SET_ID/attributes" \
 | jq -r '.[].attribute_code' | grep -qx 'ibu'; then
  echo "✅ 'ibu' er tilordnet set=$SET_ID"
else
  echo "⚙️  'ibu' mangler i set=$SET_ID — tildeler…"
  # Hent grupper – API kan returnere enten et objekt med .items, et tall (group_id) eller en liste
  GROUPS="$(curl -g -sS -H "Authorization: Bearer $ADMIN_JWT" \
    "$V1/products/attribute-sets/groups/list?searchCriteria[filterGroups][0][filters][0][field]=attribute_set_id&searchCriteria[filterGroups][0][filters][0][value]=$SET_ID&searchCriteria[filterGroups][0][filters][0][condition_type]=eq&searchCriteria[pageSize]=200")"

  GROUP_ID="$(
    echo "$GROUPS" | jq -r '
      if type=="number" then tostring
      elif type=="array" then
        (map(select((.attribute_group_name|tostring|ascii_downcase)=="general"))[0].attribute_group_id // .[0].attribute_group_id // empty)
      elif type=="object" then
        ((.items // [])
          | (map(select((.attribute_group_name|tostring|ascii_downcase)=="general"))[0].attribute_group_id
            // (.[0]?.attribute_group_id) // empty))
      else empty end
    '
  )"
  GROUP_ID="${GROUP_ID:-20}"
  echo "   attribute_group_id=$GROUP_ID"

  ASSIGN_RES="$(curl -sS -X POST "$V1/products/attribute-sets/attributes" \
    -H "Authorization: Bearer $ADMIN_JWT" \
    -H 'Content-Type: application/json' \
    --data "{\"attributeSetId\":$SET_ID,\"attributeGroupId\":$GROUP_ID,\"attributeCode\":\"ibu\",\"sortOrder\":10}")"

  echo "$ASSIGN_RES" | jq -r '.message? // "OK or already assigned"'
fi

# --- Lagre selve verdien ---
echo "💾 Lagrer IBU-verdi i Magento …"
PUT_RES="$(curl -sS -X PUT "$V1/products/$SKU" \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H 'Content-Type: application/json' \
  --data '{"product":{"sku":"'"$SKU"'","custom_attributes":[{"attribute_code":"ibu","value":"'"$IBU"'"}]}}')"

echo "$PUT_RES" | jq 'if type=="object" then {sku, id, updated_at} else . end'

# --- Verifiser ---
echo "🔎 Verifiserer lagret verdi:"
curl -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/$SKU" \
 | jq '.custom_attributes[]? | select(.attribute_code=="ibu")'
