#!/bin/bash
set -euo pipefail

SKU_ARG="${1:-}"

need() {
  local key="$1" val="${!key-}"; if [ -n "${val:-}" ]; then echo "$val"; return 0; fi
  local f; for f in .env.local .env; do
    if [ -f "$f" ]; then
      val="$(grep -E "^[[:space:]]*${key}=" "$f" | tail -n1 | sed -E "s/^[[:space:]]*${key}=//" | sed -E "s/^['\"]?(.*)['\"]?$/\1/")"
      if [ -n "$val" ]; then echo "$val"; return 0; fi
    fi
  done; echo ""
}

BASE_RAW="$(need MAGENTO_BASE_URL)"; [ -n "$BASE_RAW" ] || BASE_RAW="$(need MAGENTO_URL)"
if [ -z "$BASE_RAW" ]; then echo "❌ Sett MAGENTO_URL eller MAGENTO_BASE_URL"; exit 1; fi
BASE_RAW="${BASE_RAW%/}"
[[ "$BASE_RAW" == *"/rest" ]] || BASE_RAW="$BASE_RAW/rest"
BASE_V1="$BASE_RAW/V1/"

PREFER_ADMIN="$(need MAGENTO_PREFER_ADMIN_TOKEN)"
TOKEN="$(need MAGENTO_TOKEN)"

get_admin_token() {
  ./tools/magento-admin-token.sh
}

ensure_admin_token() {
  if [ "$PREFER_ADMIN" = "1" ] || [ -z "$TOKEN" ]; then
    TOKEN="$(get_admin_token)"
  fi
}

auth_headers() { echo "-H" "Authorization: Bearer $TOKEN" "-H" "Content-Type: application/json"; }

echo "🔎 Base: $BASE_V1"

# Sørg for admin-token
ensure_admin_token

# Sjekk om 'ibu' finnes, hvis 401 → hent admin-token og prøv igjen
check_attr() {
  curl -s -o /dev/null -w "%{http_code}" "${BASE_V1}products/attributes/ibu" $(auth_headers)
}
code="$(check_attr)"
if [ "$code" = "401" ]; then
  echo "ℹ️  Fikk 401 ved lesing av attributt – henter admin-token og prøver igjen..."
  TOKEN="$(get_admin_token)"; code="$(check_attr)"
fi

if [ "$code" = "200" ]; then
  echo "✅ 'ibu' finnes allerede."
else
  echo "🛠  Oppretter attributt 'ibu' ..."
  payload='{"attribute":{"attribute_code":"ibu","frontend_input":"text","default_frontend_label":"IBU","is_required":false,"is_unique":false,"is_user_defined":1,"is_global":1,"is_visible":true,"is_searchable":false,"is_visible_in_advanced_search":false,"is_comparable":false,"is_filterable":false,"is_html_allowed_on_front":false,"is_visible_on_front":false,"used_for_price_rules":false,"is_wysiwyg_enabled":false,"is_used_for_promo_rules":false,"frontend_labels":[{"store_id":0,"label":"IBU"}]}}'
  resp=$(curl -s -w "\n%{http_code}" -X POST "${BASE_V1}products/attributes" $(auth_headers) -d "$payload")
  http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [ "$http" != "200" ] && [ "$http" != "201" ]; then
    echo "❌ Opprettelse feilet (HTTP $http)"; echo "$body"; exit 1
  fi
  echo "✅ Opprettet 'ibu'."
fi

# Finn attribute set
ATTR_SET_ID="4"
if [ -n "$SKU_ARG" ]; then
  echo "🔎 Leser attribute_set_id for SKU=$SKU_ARG ..."
  resp=$(curl -s -w "\n%{http_code}" "${BASE_V1}products/${SKU_ARG}" $(auth_headers))
  http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [ "$http" = "200" ]; then
    ATTR_SET_ID="$(node -e 'const d=JSON.parse(process.argv[1]||"{}");console.log(d.attribute_set_id||"")' "$body" )"
    [ -n "$ATTR_SET_ID" ] || ATTR_SET_ID="4"
    echo "✅ attribute_set_id=$ATTR_SET_ID"
  else
    echo "ℹ️  Fant ikke produkt (HTTP $http) – bruker fallback set 4"
  fi
else
  echo "ℹ️  Ingen SKU oppgitt – bruker attribute_set_id=4"
fi

# Finn attribute group i settet
resp=$(curl -s -w "\n%{http_code}" "${BASE_V1}products/attribute-sets/groups/list?searchCriteria[filterGroups][0][filters][0][field]=attribute_set_id&searchCriteria[filterGroups][0][filters][0][value]=${ATTR_SET_ID}&searchCriteria[filterGroups][0][filters][0][condition_type]=eq" $(auth_headers))
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
if [ "$http" != "200" ]; then echo "❌ Henting av grupper feilet (HTTP $http)"; echo "$body"; exit 1; fi

GROUP_ID=$(node -e '
const d=JSON.parse(process.argv[1]||"{}");const items=d.items||[];
let g=items.find(x => (x.attribute_group_name||"").toLowerCase()==="general")||items[0];
console.log(g ? g.attribute_group_id : "");
' "$body")
[ -n "$GROUP_ID" ] || { echo "❌ Fant ingen attribute_group_id i set ${ATTR_SET_ID}"; exit 1; }
echo "✅ Bruker attribute_group_id=$GROUP_ID"

# Tilordne 'ibu' i settet (ignorer "already assigned")
assignPayload="{\"attributeSetId\":${ATTR_SET_ID},\"attributeGroupId\":${GROUP_ID},\"attributeCode\":\"ibu\",\"sortOrder\":10}"
resp=$(curl -s -w "\n%{http_code}" -X POST "${BASE_V1}products/attribute-sets/attributes" $(auth_headers) -d "$assignPayload")
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
if [ "$http" = "400" ] && echo "$body" | grep -qi "already assigned"; then
  echo "ℹ️  'ibu' var allerede tilordnet set ${ATTR_SET_ID}."
elif [ "$http" != "200" ] && [ "$http" != "201" ]; then
  echo "❌ Tilordning feilet (HTTP $http)"; echo "$body"; exit 1
else
  echo "✅ 'ibu' tilordnet set ${ATTR_SET_ID}."
fi

echo "🎉 Ferdig."
