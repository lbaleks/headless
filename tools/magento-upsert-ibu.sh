#!/bin/bash
set -euo pipefail

BASE="${MAGENTO_URL%/}"
TOKEN="${MAGENTO_TOKEN:-}"

if [ -z "${BASE:-}" ] || [ -z "${TOKEN:-}" ]; then
  echo "❌ Sett MAGENTO_URL og MAGENTO_TOKEN i .env.local og restart dev først."
  exit 1
fi

hdrAuth=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")

echo "🔎 Sjekker om attributt 'ibu' finnes..."
code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}V1/products/attributes/ibu" "${hdrAuth[@]}")
if [ "$code" = "200" ]; then
  echo "✅ 'ibu' finnes allerede."
else
  echo "🛠  Oppretter attributt 'ibu'..."
  # Enkel tekst-attributt, global scope. Juster label om ønskelig.
  payload='{
    "attribute": {
      "attribute_code": "ibu",
      "frontend_input": "text",
      "default_frontend_label": "IBU",
      "is_required": false,
      "is_unique": false,
      "is_user_defined": 1,
      "is_global": 1,
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
  }'
  resp=$(curl -s -w "\n%{http_code}" -X POST "${BASE}V1/products/attributes" "${hdrAuth[@]}" -d "$payload")
  http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [ "$http" != "200" ] && [ "$http" != "201" ]; then
    echo "❌ Klarte ikke opprette 'ibu' (HTTP $http)"; echo "$body"; exit 1
  fi
  echo "✅ Opprettet 'ibu'."
fi

# Finn Attribute Set (her bruker vi standard attributtsett 4; juster om dine produkter bruker et annet)
ATTR_SET_ID=4

echo "🔎 Henter attribute groups for attribute_set_id=$ATTR_SET_ID ..."
resp=$(curl -s -w "\n%{http_code}" "${BASE}V1/products/attribute-sets/groups/list?searchCriteria[filterGroups][0][filters][0][field]=attribute_set_id&searchCriteria[filterGroups][0][filters][0][value]=${ATTR_SET_ID}&searchCriteria[filterGroups][0][filters][0][condition_type]=eq" "${hdrAuth[@]}")
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
if [ "$http" != "200" ]; then
  echo "❌ Kunne ikke hente grupper (HTTP $http)"; echo "$body"; exit 1
fi

# Plukk gruppeId for "General" eller første gruppe
groupId=$(node -e '
const data = JSON.parse(process.argv[1] || "{}");
const items = data.items || [];
let g = items.find(x => (x.attribute_group_name||"").toLowerCase()==="general");
if(!g) g = items[0];
console.log(g ? g.attribute_group_id : "");
' "$body")

if [ -z "$groupId" ]; then
  echo "❌ Fant ingen attribute_group_id i sett $ATTR_SET_ID"
  exit 1
fi
echo "✅ Bruker attribute_group_id=$groupId"

echo "🛠  Legger 'ibu' inn i attribute set $ATTR_SET_ID / group $groupId ..."
assignPayload=$(cat <<JSON
{
  "attributeSetId": ${ATTR_SET_ID},
  "attributeGroupId": ${groupId},
  "attributeCode": "ibu",
  "sortOrder": 10
}
JSON
)
resp=$(curl -s -w "\n%{http_code}" -X POST "${BASE}V1/products/attribute-sets/attributes" "${hdrAuth[@]}" -d "$assignPayload")
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"

if [ "$http" = "400" ] && echo "$body" | grep -qi "already assigned"; then
  echo "ℹ️  'ibu' er allerede tilordnet settet."
elif [ "$http" != "200" ] && [ "$http" != "201" ]; then
  echo "❌ Klarte ikke tilordne 'ibu' (HTTP $http)"; echo "$body"; exit 1
else
  echo "✅ 'ibu' tilordnet i set $ATTR_SET_ID."
fi

echo "🎉 Ferdig. Du kan nå lagre IBU på produkter i dette attributtsettet."
