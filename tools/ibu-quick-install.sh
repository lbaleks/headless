#!/usr/bin/env bash
set -euo pipefail

SKU="${1:-}"
if [[ -z "$SKU" ]]; then
  echo "Bruk: tools/ibu-quick-install.sh <SKU>" >&2
  exit 1
fi

# --- 0) Krav ---
command -v jq >/dev/null || { echo "❌ Mangler 'jq' (brew install jq)"; exit 1; }
[[ -f .env.local ]] || { echo "❌ Mangler .env.local"; exit 1; }

# --- 1) Les env fra .env.local (kun MAGENTO_*) ---
while IFS= read -r raw; do
  raw="${raw%$'\r'}"
  [[ -z "$raw" || "$raw" =~ ^[[:space:]]*# ]] && continue
  [[ "$raw" =~ ^(MAGENTO_|MAGENTO_ADMIN_|MAGENTO_PREFER_ADMIN_TOKEN) ]] || continue
  key="${raw%%=*}"; val="${raw#*=}"
  if [[ "${val:0:1}" == "\"" && "${val: -1}" == "\"" ]]; then val="${val:1:${#val}-2}"; fi
  if [[ "${val:0:1}" == "'"  && "${val: -1}" == "'"  ]]; then val="${val:1:${#val}-2}"; fi
  export "${key}"="${val}"
done < .env.local

BASE_RAW="${MAGENTO_URL:-${MAGENTO_BASE_URL:-}}"
[[ -n "${BASE_RAW}" ]] || { echo "❌ Sett MAGENTO_URL eller MAGENTO_BASE_URL i .env.local"; exit 1; }
BASE_RAW="${BASE_RAW%/}"
if [[ "$BASE_RAW" =~ /rest$ ]]; then
  REST="$BASE_RAW"
elif [[ "$BASE_RAW" =~ /rest/ ]]; then
  REST="${BASE_RAW%/V1}"
else
  REST="$BASE_RAW/rest"
fi
V1="$REST/V1"

echo "🔎 Base: $V1"

# --- 2) Admin-token (foretrekk admin hvis mulig) ---
get_admin_token() {
  [[ -n "${MAGENTO_ADMIN_USERNAME:-}" && -n "${MAGENTO_ADMIN_PASSWORD:-}" ]] || return 1
  curl -sS -X POST "$V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data "{\"username\":\"${MAGENTO_ADMIN_USERNAME}\",\"password\":\"${MAGENTO_ADMIN_PASSWORD}\"}" \
    | tr -d '"'
}
if [[ -z "${MAGENTO_TOKEN:-}" ]]; then
  echo "🔐 Henter admin-token…"
  MAGENTO_TOKEN="$(get_admin_token || true)"
  [[ -n "$MAGENTO_TOKEN" ]] || { echo "❌ Fikk ikke admin-token. Sjekk brukernavn/pass i .env.local"; exit 1; }
fi

AUTH=(-H "Authorization: Bearer ${MAGENTO_TOKEN}")

# --- 3) Opprett attributt 'ibu' hvis den ikke finnes ---
if curl -sS -o /dev/null -w "%{http_code}" "${AUTH[@]}" "$V1/products/attributes/ibu" | grep -qE '^(200)$'; then
  echo "✅ Attributt 'ibu' finnes allerede"
else
  echo "🛠  Oppretter attributt 'ibu'…"
  payload='{"attribute":{"attribute_code":"ibu","frontend_input":"text","default_frontend_label":"IBU","is_user_defined":true,"is_required":false,"frontend_labels":[{"store_id":0,"label":"IBU"}]}}'
  code="$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${AUTH[@]}" -H 'Content-Type: application/json' --data "$payload" "$V1/products/attributes" || true)"
  if [[ "$code" != "200" && "$code" != "201" ]]; then
    echo "❌ Klarte ikke å opprette 'ibu' (HTTP $code). Har brukeren tilstrekkelige rettigheter?" ; exit 1
  fi
  echo "✅ Opprettet 'ibu'"
fi

# --- 4) Finn attribute_set_id for SKU ---
echo "🔎 Henter attribute_set_id for $SKU"
SET_ID="$(curl -sS "${AUTH[@]}" "$V1/products/$SKU" | jq -r '.attribute_set_id // empty')"
[[ -n "$SET_ID" ]] || { echo "❌ Fant ikke produkt/SKU ($SKU) eller attribute_set_id"; exit 1; }

# --- 5) Finn en attribute_group_id i settet (prøv 'General'/'Generelt', ellers første) ---
Q='searchCriteria%5BfilterGroups%5D%5B0%5D%5Bfilters%5D%5B0%5D%5Bfield%5D=attribute_set_id&searchCriteria%5BfilterGroups%5D%5B0%5D%5Bfilters%5D%5B0%5D%5Bvalue%5D='"$SET_ID"'&searchCriteria%5BfilterGroups%5D%5B0%5D%5Bfilters%5D%5B0%5D%5Bcondition_type%5D=eq'
GROUPS_JSON="$(curl -sS --globoff "${AUTH[@]}" "$V1/products/attribute-sets/groups/list?$Q")"
GROUP_ID="$(echo "$GROUPS_JSON" | jq -r '.items[] | select((.attribute_group_name|ascii_downcase)=="general" or (.attribute_group_name|ascii_downcase)=="generelt") .attribute_group_id // empty' | head -n1)"
if [[ -z "$GROUP_ID" ]]; then
  GROUP_ID="$(echo "$GROUPS_JSON" | jq -r '.items[0].attribute_group_id // empty')"
fi
[[ -n "$GROUP_ID" ]] || { echo "❌ Fant ikke attribute_group_id for set=$SET_ID"; exit 1; }
echo "✅ attribute_set_id=$SET_ID, attribute_group_id=$GROUP_ID"

# --- 6) Legg 'ibu' i settet (idempotent; 400 betyr ofte 'allerede tilordnet') ---
echo "🧩 Tilordner 'ibu' til set=$SET_ID / group=$GROUP_ID"
assign_payload="{\"attributeSetId\":${SET_ID},\"attributeGroupId\":${GROUP_ID},\"attributeCode\":\"ibu\",\"sortOrder\":10}"
assign_code="$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${AUTH[@]}" -H 'Content-Type: application/json' --data "$assign_payload" "$V1/products/attribute-sets/attributes" || true)"
if [[ "$assign_code" == "200" || "$assign_code" == "201" ]]; then
  echo "✅ Tilordnet"
elif [[ "$assign_code" == "400" ]]; then
  echo "ℹ️  Ser ut som 'ibu' allerede er tilordnet dette settet"
else
  echo "❌ Tilordning feilet (HTTP $assign_code) – fortsetter, men oppdatering kan feile"
fi

# --- 7) Rask verifisering: oppdater via lokalt API ---
if curl -sS -o /dev/null -w "%{http_code}" http://localhost:3000/ >/dev/null 2>&1; then
  echo "🧪 Tester PATCH via /api/products/update-attributes …"
  patch_payload='{"sku":"'"$SKU"'","attributes":{"ibu":"37"}}'
  http="$(curl -sS -o /dev/null -w "%{http_code}" -X PATCH 'http://localhost:3000/api/products/update-attributes' -H 'Content-Type: application/json' --data "$patch_payload" || true)"
  if [[ "$http" == "200" ]]; then
    echo "✅ PATCH OK. Sjekker at feltene synes…"
    curl -sS "http://localhost:3000/api/products/$SKU" \
      | jq '.custom_attributes[] | select(.attribute_code=="ibu" or .attribute_code=="cfg_ibu" or .attribute_code=="akeneo_ibu")'
  else
    echo "⚠️  PATCH ga HTTP $http – men installasjon av attributt/set ser ferdig ut."
  fi
else
  echo "ℹ️  Skipper lokal PATCH-test (dev-server ikke oppe)."
fi

echo "🎉 Ferdig!"