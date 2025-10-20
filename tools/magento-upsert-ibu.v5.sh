#!/bin/bash
set -euo pipefail
set +H
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
[ -n "$BASE_RAW" ] || { echo "❌ Sett MAGENTO_URL eller MAGENTO_BASE_URL"; exit 1; }
BASE_RAW="${BASE_RAW%/}"; [[ "$BASE_RAW" == *"/rest" ]] || BASE_RAW="$BASE_RAW/rest"
BASE_V1="$BASE_RAW/V1/"

TOKEN="${MAGENTO_TOKEN:-$(need MAGENTO_TOKEN)}"

# Hvis vi fortsatt ikke har token → hent admin-token (v3)
if [ -z "$TOKEN" ]; then
  echo "ℹ️ Henter admin-token (mangler MAGENTO_TOKEN i env/.env.local) ..."
  TOKEN="$(./tools/magento-admin-token.v3.sh)"
fi

auth() { echo "-H" "Authorization: Bearer $TOKEN" "-H" "Content-Type: application/json"; }

echo "🔎 Base: $BASE_V1"

# 1) Sjekk/lag 'ibu'
check_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_V1}products/attributes/ibu" $(auth))
if [ "$check_code" != "200" ]; then
  echo "🛠  Oppretter attributt 'ibu' ..."
  payload='{"attribute":{"attribute_code":"ibu","frontend_input":"text","default_frontend_label":"IBU","is_required":false,"is_unique":false,"is_user_defined":1,"is_global":1,"is_visible":true,"is_searchable":false,"is_visible_in_advanced_search":false,"is_comparable":false,"is_filterable":false,"is_html_allowed_on_front":false,"is_visible_on_front":false,"used_for_price_rules":false,"is_wysiwyg_enabled":false,"is_used_for_promo_rules":false,"frontend_labels":[{"store_id":0,"label":"IBU"}]}}'
  resp=$(curl -s -w "\n%{http_code}" -X POST "${BASE_V1}products/attributes" $(auth) -d "$payload")
  http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  [ "$http" = "200" -o "$http" = "201" ] || { echo "❌ Opprettelse feilet (HTTP $http)"; echo "$body"; exit 1; }
  echo "✅ Opprettet 'ibu'."
else
  echo "✅ 'ibu' finnes allerede."
fi

# 2) Finn attribute_set_id (fra SKU om gitt, ellers 4)
ATTR_SET_ID="4"
if [ -n "$SKU_ARG" ]; then
  echo "🔎 Leser attribute_set_id for $SKU_ARG ..."
  resp=$(curl -s -w "\n%{http_code}" "${BASE_V1}products/${SKU_ARG}" $(auth))
  http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [ "$http" = "200" ]; then
    id=$(node -e 'const d=JSON.parse(process.argv[1]||"{}");console.log(d.attribute_set_id||"")' "$body")
    [ -n "$id" ] && ATTR_SET_ID="$id"
    echo "✅ attribute_set_id=$ATTR_SET_ID"
  else
    echo "ℹ️ Fikk $http fra products/${SKU_ARG} – bruker 4"
  fi
else
  echo "ℹ️ Ingen SKU gitt – bruker 4"
fi

# 3) Hent gruppe (General) i settet
resp=$(curl -s -w "\n%{http_code}" "${BASE_V1}products/attribute-sets/groups/list?searchCriteria[filterGroups][0][filters][0][field]=attribute_set_id&searchCriteria[filterGroups][0][filters][0][value]=${ATTR_SET_ID}&searchCriteria[filterGroups][0][filters][0][condition_type]=eq" $(auth))
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
[ "$http" = "200" ] || { echo "❌ Henting av grupper feilet (HTTP $http)"; echo "$body"; exit 1; }
GROUP_ID=$(node -e '
const d=JSON.parse(process.argv[1]||"{}");const items=d.items||[];
let g=items.find(x => (x.attribute_group_name||"").toLowerCase()==="general")||items[0];
console.log(g ? g.attribute_group_id : "");
' "$body")
[ -n "$GROUP_ID" ] || { echo "❌ Fant ingen attribute_group_id"; exit 1; }
echo "✅ attribute_group_id=$GROUP_ID"

# 4) Tilordne 'ibu' til attribute set
assign='{"attributeSetId":'"$ATTR_SET_ID"',"attributeGroupId":'"$GROUP_ID"',"attributeCode":"ibu","sortOrder":10}'
resp=$(curl -s -w "\n%{http_code}" -X POST "${BASE_V1}products/attribute-sets/attributes" $(auth) -d "$assign")
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
if [ "$http" = "400" ] && echo "$body" | grep -qi "already assigned"; then
  echo "ℹ️ 'ibu' er allerede tilordnet set $ATTR_SET_ID."
elif [ "$http" = "200" -o "$http" = "201" ]; then
  echo "✅ 'ibu' tilordnet set $ATTR_SET_ID."
else
  echo "❌ Tilordning feilet (HTTP $http)"; echo "$body"; exit 1
fi

echo "🎉 Ferdig."
