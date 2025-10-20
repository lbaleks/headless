#!/bin/bash
set -euo pipefail

SKU_ARG="${1:-}"

# --- Hent env: forsøk miljøvariabler, ellers les .env.local/.env ---
need() {
  local key="$1"
  local val="${!key-}"
  if [ -n "${val:-}" ]; then echo "$val"; return 0; fi
  local file
  for file in .env.local .env; do
    if [ -f "$file" ]; then
      val="$(grep -E "^[[:space:]]*${key}=" "$file" | tail -n1 | sed -E "s/^[[:space:]]*${key}=//" | sed -E "s/^['\"]?(.*)['\"]?$/\1/")"
      if [ -n "$val" ]; then echo "$val"; return 0; fi
    fi
  done
  echo ""
}

MAGENTO_URL="$(need MAGENTO_URL)"
MAGENTO_BASE_URL="$(need MAGENTO_BASE_URL)"
MAGENTO_TOKEN="$(need MAGENTO_TOKEN)"

if [ -z "$MAGENTO_TOKEN" ]; then
  echo "❌ Mangler MAGENTO_TOKEN i miljø/.env.local/.env"
  exit 1
fi

# Normaliser base til .../rest/V1
normalize_base_v1() {
  local url="$1"
  url="${url%/}"
  if [[ "$url" != *"/rest" && "$url" != *"/rest/" ]]; then
    url="$url/rest"
  fi
  echo "${url%/}/V1/"
}

if [ -n "$MAGENTO_BASE_URL" ]; then
  # MAGENTO_BASE_URL forventes å være .../rest
  BASE_V1="$(normalize_base_v1 "$MAGENTO_BASE_URL")"
elif [ -n "$MAGENTO_URL" ]; then
  BASE_V1="$(normalize_base_v1 "$MAGENTO_URL")"
else
  echo "❌ Sett enten MAGENTO_BASE_URL eller MAGENTO_URL"
  exit 1
fi

AUTH=(-H "Authorization: Bearer $MAGENTO_TOKEN" -H "Content-Type: application/json")

echo "🔎 Bruker base: ${BASE_V1}"

# 1) Finnes 'ibu' allerede?
code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_V1}products/attributes/ibu" "${AUTH[@]}")
if [ "$code" = "200" ]; then
  echo "✅ Attributt 'ibu' finnes allerede."
else
  echo "🛠  Oppretter attributt 'ibu'…"
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
  resp=$(curl -s -w "\n%{http_code}" -X POST "${BASE_V1}products/attributes" "${AUTH[@]}" -d "$payload")
  http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [ "$http" != "200" ] && [ "$http" != "201" ]; then
    echo "❌ Opprettelse feilet (HTTP $http)"; echo "$body"; exit 1
  fi
  echo "✅ Opprettet 'ibu'."
fi

# 2) Finn attribute set å tilordne til
ATTR_SET_ID="4"
if [ -n "$SKU_ARG" ]; then
  echo "�� Leser attribute_set_id for SKU=${SKU_ARG}…"
  resp=$(curl -s -w "\n%{http_code}" "${BASE_V1}products/${SKU_ARG}" "${AUTH[@]}")
  http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [ "$http" = "200" ]; then
    id=$(node -e 'const d=JSON.parse(process.argv[1]||"{}");console.log(d.attribute_set_id||"")' "$body")
    if [ -n "$id" ]; then ATTR_SET_ID="$id"; fi
    echo "✅ attribute_set_id=${ATTR_SET_ID}"
  else
    echo "ℹ️  Fikk ikke produkt (${http}) – bruker fallback attribute_set_id=4"
  fi
else
  echo "ℹ️  Ingen SKU oppgitt – bruker attribute_set_id=4"
fi

# 3) Hent gruppe (General) i settet
resp=$(curl -s -w "\n%{http_code}" "${BASE_V1}products/attribute-sets/groups/list?searchCriteria[filterGroups][0][filters][0][field]=attribute_set_id&searchCriteria[filterGroups][0][filters][0][value]=${ATTR_SET_ID}&searchCriteria[filterGroups][0][filters][0][condition_type]=eq" "${AUTH[@]}")
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
if [ "$http" != "200" ]; then
  echo "❌ Kunne ikke hente grupper for set ${ATTR_SET_ID} (HTTP $http)"; echo "$body"; exit 1
fi

GROUP_ID=$(node -e '
const d=JSON.parse(process.argv[1]||"{}");const items=d.items||[];
let g=items.find(x => (x.attribute_group_name||"").toLowerCase()==="general")||items[0];
console.log(g ? g.attribute_group_id : "");
' "$body")

if [ -z "$GROUP_ID" ]; then
  echo "❌ Fant ingen attribute_group_id i set ${ATTR_SET_ID}"; exit 1
fi
echo "✅ Bruker attribute_group_id=${GROUP_ID}"

# 4) Tilordne 'ibu' til settet
assignPayload=$(cat <<JSON
{
  "attributeSetId": ${ATTR_SET_ID},
  "attributeGroupId": ${GROUP_ID},
  "attributeCode": "ibu",
  "sortOrder": 10
}
JSON
)
resp=$(curl -s -w "\n%{http_code}" -X POST "${BASE_V1}products/attribute-sets/attributes" "${AUTH[@]}" -d "$assignPayload")
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"

if [ "$http" = "400" ] && echo "$body" | grep -qi "already assigned"; then
  echo "ℹ️  'ibu' er allerede tilordnet set ${ATTR_SET_ID}."
elif [ "$http" != "200" ] && [ "$http" != "201" ]; then
  echo "❌ Tilordning feilet (HTTP $http)"; echo "$body"; exit 1
else
  echo "✅ 'ibu' tilordnet set ${ATTR_SET_ID}."
fi

echo "🎉 Ferdig."
