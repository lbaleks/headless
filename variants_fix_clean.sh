#!/usr/bin/env bash
# variants_fix_clean.sh

# ---- SIKKER OPPSETT ----
set +H 2>/dev/null || true   # slå av history expansion hvis shell støtter det
export LC_ALL=C.UTF-8

# ---- KREVER DISSE VARIABLENE ----
: "${M2_BASE_URL:?Sett M2_BASE_URL, f.eks. https://m2-dev.litebrygg.no}"
: "${AUTH:?Sett AUTH=Authorization: Bearer <token> }"

say() { printf "%b\n" "$*"; }
curlj() { curl -sS "$@" ; }

# ---- HENT/OPPRETT RED/BLUE ----
say "🔎 Henter farge-opsjoner (Red/Blue)…"
LIST_JSON=$(curlj -H "$AUTH" "$M2_BASE_URL/rest/V1/products/attributes/color/options")

get_opt_id () {
  printf '%s' "$LIST_JSON" | jq -r --arg L "$1" '.[] | select(.label==$L) | .value'
}

RED_ID=$(get_opt_id "Red")
BLUE_ID=$(get_opt_id "Blue")

if [ -z "$RED_ID" ] || [ "$RED_ID" = "null" ]; then
  say "➕ Lager 'Red'…"
  curlj -X POST -H "$AUTH" -H 'Content-Type: application/json' \
    --data-binary '{"option":{"label":"Red","sort_order":0,"is_default":false}}' \
    "$M2_BASE_URL/rest/V1/products/attributes/color/options" >/dev/null
fi

if [ -z "$BLUE_ID" ] || [ "$BLUE_ID" = "null" ]; then
  say "➕ Lager 'Blue'…"
  curlj -X POST -H "$AUTH" -H 'Content-Type: application/json' \
    --data-binary '{"option":{"label":"Blue","sort_order":0,"is_default":false}}' \
    "$M2_BASE_URL/rest/V1/products/attributes/color/options" >/dev/null
fi

# refresh liste
LIST_JSON=$(curlj -H "$AUTH" "$M2_BASE_URL/rest/V1/products/attributes/color/options")
RED_ID=$(printf '%s' "$LIST_JSON" | jq -r '.[] | select(.label=="Red")  | .value')
BLUE_ID=$(printf '%s' "$LIST_JSON" | jq -r '.[] | select(.label=="Blue") | .value')
say "✅ RED_ID=$RED_ID  BLUE_ID=$BLUE_ID"

if [ -z "$RED_ID" ] || [ -z "$BLUE_ID" ] || [ "$RED_ID" = "null" ] || [ "$BLUE_ID" = "null" ]; then
  say "❌ Fikk ikke hentet option_id for Red/Blue. Avbryter."
  exit 1
fi

# ---- FINN ET ATTRIBUTE-SET SOM HAR 'color' ----
say "🔎 Leter etter attribute set som inneholder 'color'…"
SETS_JSON=$(curlj -H "$AUTH" "$M2_BASE_URL/rest/V1/products/attribute-sets/sets/list?searchCriteria[pageSize]=200")

SET_WITH_COLOR=""
for sid in $(printf '%s\n' "$SETS_JSON" | jq -r '.items[].attribute_set_id'); do
  HAS_COLOR=$(curlj -H "$AUTH" "$M2_BASE_URL/rest/V1/products/attribute-sets/$sid/attributes" \
               | jq -r 'map(.attribute_code=="color") | any')
  if [ "$HAS_COLORx" = "truex" ]; then
    SET_WITH_COLOR="$sid"
    break
  fi
done

if [ -z "$SET_WITH_COLOR" ]; then
  say "❌ Fant ikke noe attribute set med 'color'. Trenger rettigheter/konfig i M2."
  exit 1
fi
say "✅ SET_WITH_COLOR=$SET_WITH_COLOR"

# ---- OPPDATER SIMPLE-PRODUKTENE MED COLOR + RIKTIG SET ----
update_simple () {
  local SKU="$1" COLOR_VAL="$2"
  say "✏️  Oppdaterer $SKU (color=$COLOR_VAL, set=$SET_WITH_COLOR)…"
  jq -n --arg sku "$SKU" --arg set "$SET_WITH_COLOR" --arg color "$COLOR_VAL" '
    {
      product:{
        sku:$sku, type_id:"simple",
        attribute_set_id: ($set|tonumber),
        visibility:1, price:399, status:1, weight:1,
        custom_attributes:[{attribute_code:"color", value:$color}]
      }
    }' \
  | curlj -X PUT -H "$AUTH" -H 'Content-Type: application/json' \
          --data-binary @- "$M2_BASE_URL/rest/V1/products/$SKU" \
  | jq -c '{sku, type_id} // .'
}

update_simple "TEST-RED"  "$RED_ID"
update_simple "TEST-BLUE" "$BLUE_ID"

# Verifiser
RED_CUR=$(curlj -H "$AUTH" "$M2_BASE_URL/rest/V1/products/TEST-RED"  | jq -r '.custom_attributes[]? | select(.attribute_code=="color") | .value')
BLUE_CUR=$(curlj -H "$AUTH" "$M2_BASE_URL/rest/V1/products/TEST-BLUE" | jq -r '.custom_attributes[]? | select(.attribute_code=="color") | .value')
say "🔍 TEST-RED.color=$RED_CUR  TEST-BLUE.color=$BLUE_CUR"

if [ "$RED_CUR" != "$RED_ID" ] || [ "$BLUE_CUR" != "$BLUE_ID" ]; then
  say "❌ Color ble ikke lagret riktig på simple-produktene. Avbryter."
  exit 1
fi

# ---- SØRG FOR AT TEST-CFG HAR CONFIGURABLE OPTION = COLOR ----
COLOR_ATTR_ID=$(curlj -H "$AUTH" "$M2_BASE_URL/rest/V1/products/attributes/color" | jq -r '.attribute_id')
say "🧩 Setter configurable option (color) på TEST-CFG (id=$COLOR_ATTR_ID)…"
# idempotent: ignorer hvis allerede finnes
jq -n --arg aid "$COLOR_ATTR_ID" --arg red "$RED_ID" --arg blue "$BLUE_ID" '
  {"option":{"attribute_id":$aid,"label":"color","position":0,"is_use_default":true,
             "values":[{"value_index":($red|tonumber)},{"value_index":($blue|tonumber)}]}}' \
| curlj -X POST -H "$AUTH" -H 'Content-Type: application/json' \
        --data-binary @- "$M2_BASE_URL/rest/V1/configurable-products/TEST-CFG/options" \
| jq -c '.' >/dev/null 2>&1 || true

# ---- KOBLE BARN ----
attach_child () {
  local C="$1"
  say "🔗 Knytter $C til TEST-CFG…"
  curlj -X POST -H "$AUTH" -H 'Content-Type: application/json' \
    --data-binary "$(jq -n --arg c "$C" '{childSku:$c}')" \
    "$M2_BASE_URL/rest/V1/configurable-products/TEST-CFG/child" \
  | jq -c '. // {}' >/dev/null 2>&1 || true
}
attach_child "TEST-RED"
attach_child "TEST-BLUE"

# ---- VIS RESULTAT ----
CHILDREN=$(curlj -H "$AUTH" "$M2_BASE_URL/rest/V1/configurable-products/TEST-CFG/children" | jq -c 'map(.sku)')
say "✅ Children of TEST-CFG → $CHILDREN"