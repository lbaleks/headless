#!/usr/bin/env bash
set -euo pipefail

# --- Autoload .env.local om nødvendige vars mangler ---
if [[ -z "${MAGENTO_URL:-}" && -z "${MAGENTO_BASE_URL:-}" && -f ".env.local" ]]; then
  while IFS= read -r line; do
    [[ $line =~ ^MAGENTO_[A-Z0-9_]+= ]] || continue
    key=${line%%=*}; val=${line#*=}
    val=${val%$'\r'}
    [[ $val == \"*\" && $val == *\" ]] && val=${val:1:-1}
    [[ $val == \'*\' && $val == *\' ]] && val=${val:1:-1}
    export "$key=$val"
  done < .env.local
fi

BASE="${MAGENTO_URL:-${MAGENTO_BASE_URL:-}}"
BASE="${BASE%/}"
if [[ -z "${BASE}" ]]; then
  echo "❌ MAGENTO_URL eller MAGENTO_BASE_URL mangler (sett i .env.local)"
  exit 1
fi
V1="${BASE}/V1"

SKU="${1:-}"
IBU_VAL="${2:-}"
if [[ -z "${SKU}" || -z "${IBU_VAL}" ]]; then
  echo "Bruk: tools/ibu-hardening.sh <SKU> <IBU-verdi>"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ 'jq' mangler (installer jq først)"
  exit 1
fi

# --- Hent admin-token ---
if [[ -n "${MAGENTO_ADMIN_TOKEN:-}" ]]; then
  ADMIN_JWT="${MAGENTO_ADMIN_TOKEN}"
else
  if [[ -z "${MAGENTO_ADMIN_USERNAME:-}" || -z "${MAGENTO_ADMIN_PASSWORD:-}" ]]; then
    echo "❌ MAGENTO_ADMIN_USERNAME/MAGENTO_ADMIN_PASSWORD mangler (.env.local)"
    exit 1
  fi
  ADMIN_JWT="$(
    curl -sS -X POST "${V1}/integration/admin/token" \
      -H 'Content-Type: application/json' \
      --data "{\"username\":\"${MAGENTO_ADMIN_USERNAME}\",\"password\":\"${MAGENTO_ADMIN_PASSWORD}\"}" \
    | tr -d '"'
  )"
  if [[ -z "${ADMIN_JWT}" || "${ADMIN_JWT}" == '{"message":'* ]]; then
    echo "❌ Klarte ikke hente admin-token. Respons:"
    echo "${ADMIN_JWT}"
    exit 1
  fi
fi

echo "🔗 Magento V1: ${V1}"
echo "🔐 Admin-token OK"

# --- Sikre attributt 'ibu' (idempotent) ---
curl -sS -X POST "${V1}/products/attributes" \
  -H "Authorization: Bearer ${ADMIN_JWT}" \
  -H 'Content-Type: application/json' \
  --data '{
    "attribute": {
      "attribute_code": "ibu",
      "frontend_input": "text",
      "default_frontend_label": "IBU",
      "is_required": false,
      "is_unique": false,
      "is_user_defined": 1,
      "is_visible": true,
      "is_searchable": false,
      "is_visible_in_advanced_search": false,
      "is_comparable": false,
      "is_filterable": false,
      "is_html_allowed_on_front": false,
      "is_visible_on_front": false,
      "used_for_price_rules": false,
      "is_wysiwyg_enabled": false,
      "is_used_for_promo_rules": false,
      "frontend_labels": [{"store_id": 0, "label": "IBU"}]
    }
  }' >/dev/null || true
echo "🛠  Attributt 'ibu' sikret"

# --- Finn attribute_set_id for SKU ---
SET_ID="$(
  curl -sS -H "Authorization: Bearer ${ADMIN_JWT}" "${V1}/products/${SKU}" \
  | jq -r '.attribute_set_id'
)"
if [[ -z "${SET_ID}" || "${SET_ID}" == "null" ]]; then
  echo "❌ Fant ikke attribute_set_id for ${SKU}"
  exit 1
fi
echo "🔎 attribute_set_id=${SET_ID}"

# --- Hent grupper for settet robust ---
GROUPS="$(
  curl -g -sS -H "Authorization: Bearer ${ADMIN_JWT}" --get \
    --data-urlencode 'searchCriteria[filterGroups][0][filters][0][field]=attribute_set_id' \
    --data-urlencode "searchCriteria[filterGroups][0][filters][0][value]=${SET_ID}" \
    --data-urlencode 'searchCriteria[filterGroups][0][filters][0][condition_type]=eq' \
    --data-urlencode 'searchCriteria[pageSize]=200' \
    "${V1}/products/attribute-sets/groups/list"
)"

GROUP_ID="$(
  echo "${GROUPS}" | jq -r '
    (if type=="object" and (.items|type)=="array" then .items else . end)
    | (map(select((.attribute_group_name|tostring|ascii_downcase)=="general"))[0].attribute_group_id // .[0].attribute_group_id) // empty
  '
)"
if [[ -z "${GROUP_ID}" || "${GROUP_ID}" == "null" ]]; then
  echo "⚠️  Uventet groups/list-respons, viser første 400 tegn:"
  echo "${GROUPS}" | head -c 400; echo
  echo "❌ Fant ikke attribute_group_id for set=${SET_ID}"
  exit 1
fi
echo "🔎 attribute_group_id=${GROUP_ID}"

# --- Tilordne 'ibu' til sett/gruppe ---
curl -sS -X POST "${V1}/products/attribute-sets/attributes" \
  -H "Authorization: Bearer ${ADMIN_JWT}" \
  -H 'Content-Type: application/json' \
  --data "{\"attributeSetId\":${SET_ID},\"attributeGroupId\":${GROUP_ID},\"attributeCode\":\"ibu\",\"sortOrder\":10}" \
  >/dev/null || true
echo "🧩 'ibu' tilordnet set=${SET_ID} / group=${GROUP_ID}"

# --- Lagre IBU på produktet ---
curl -sS -X PUT "${V1}/products/${SKU}" \
  -H "Authorization: Bearer ${ADMIN_JWT}" \
  -H 'Content-Type: application/json' \
  --data "{\"product\":{\"sku\":\"${SKU}\",\"custom_attributes\":[{\"attribute_code\":\"ibu\",\"value\":\"${IBU_VAL}\"}]}}" \
  >/dev/null
echo "✅ Satt IBU=${IBU_VAL} på ${SKU}"

# --- Verifiser (direkte fra Magento) ---
echo "🔍 Verifiserer fra Magento:"
curl -sS -H "Authorization: Bearer ${ADMIN_JWT}" "${V1}/products/${SKU}" \
  | jq '.custom_attributes[]? | select(.attribute_code=="ibu")'
