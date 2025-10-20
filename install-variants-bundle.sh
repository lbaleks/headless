#!/usr/bin/env sh
set -eu

# --- Input -------------------------------------------------------
printf "BASE (f.eks. https://m2-dev.litebrygg.no): "
IFS= read -r BASE
[ -n "${BASE:-}" ] || { echo "BASE mangler"; exit 1; }

printf "ADMIN_USER: "
IFS= read -r ADMIN_USER
[ -n "${ADMIN_USER:-}" ] || { echo "ADMIN_USER mangler"; exit 1; }

printf "ADMIN_PASS: "
# skjul tastetrykk på macOS/Linux hvis mulig
(stty -echo 2>/dev/null || true)
IFS= read -r ADMIN_PASS
(stty echo 2>/dev/null || true)
printf "\n"

# Standard-innstillinger (kan endres i .m2-env senere)
PARENT_SKU_DEFAULT="TEST-CFG"
ATTR_CODE_DEFAULT="cfg_color"
WEBSITE_ID_DEFAULT=""
SOURCE_CODE_DEFAULT="default"
ATTR_SET_ID_DEFAULT="4"

BASE="${BASE%/}"

# --- Hent token --------------------------------------------------
echo "Henter admin token…"
AUTH_TOKEN=$(
  curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data "$(printf '{"username":"%s","password":"%s"}' "$ADMIN_USER" "$ADMIN_PASS")" \
  | sed -e 's/^"//' -e 's/"$//'
)
[ -n "$AUTH_TOKEN" ] || { echo "Kunne ikke hente token"; exit 1; }
AUTH_ADMIN="Authorization: Bearer $AUTH_TOKEN"
echo "✅ Token OK."

# --- Finn/sett WEBSITE_ID ---------------------------------------
echo "Oppdager Websites…"
WEBSITE_ID=$(
  curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/store/websites" \
  | jq -r '[.[] | select(.id!=0)][0].id'
)
[ -n "$WEBSITE_ID" ] || WEBSITE_ID="$WEBSITE_ID_DEFAULT"

# --- Skriv .m2-env ----------------------------------------------
cat > .m2-env <<EOF
# autogenerert – last inn før du kjører hjelpe­skriptene:
#   source ./.m2-env
export BASE=$(printf '%s' "$BASE")
export AUTH_ADMIN=$(printf '%s' "Authorization: Bearer $AUTH_TOKEN")
export PARENT_SKU=${PARENT_SKU_DEFAULT}
export ATTR_CODE=${ATTR_CODE_DEFAULT}
export WEBSITE_ID=${WEBSITE_ID}
export SOURCE_CODE=${SOURCE_CODE_DEFAULT}
export ATTR_SET_ID=${ATTR_SET_ID_DEFAULT}
EOF

# --- add-color.sh (robust upsert) --------------------------------
cat > add-color.sh <<"EOF"
#!/usr/bin/env sh
set -eu

: "${BASE:?BASE not set}; ${AUTH_ADMIN:?AUTH_ADMIN not set}"
: "${PARENT_SKU:=TEST-CFG}"
: "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"
: "${SOURCE_CODE:=default}"
: "${ATTR_SET_ID:=4}"

# NY farge/sku/qty:
: "${NEW_LABEL:=}"
: "${NEW_SKU:=}"
: "${NEW_QTY:=10}"
: "${NEW_VAL_ID:=}"   # valgfritt: hopp over label->value lookup

fail() { echo "❌ $*"; exit 1; }

# 1) Finn/lag value_index
VAL_ID="${NEW_VAL_ID:-}"
if [ -z "$VAL_ID" ]; then
  # Prøv å lage option (hvis ACL tillater det), ellers fall tilbake til oppslag
  CREATE_CODE=$(curl -sS -o /tmp/opt-create.json -w '%{http_code}' \
    -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data "$(jq -n --arg label "${NEW_LABEL:?NEW_LABEL mangler}" \
      '{option:{label:$label,sort_order:99,is_default:false}}')" \
    "$BASE/rest/V1/products/attributes/$ATTR_CODE/options" || true)

  if [ "$CREATE_CODE" = "200" ] || [ "$CREATE_CODE" = "201" ]; then
    VAL_ID=$(jq -r '.' </tmp/opt-create.json)
  else
    # ACL eller annet – slå opp verdi-id ved label
    OPTS=$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/products/attributes/$ATTR_CODE/options")
    VAL_ID=$(printf '%s' "$OPTS" | jq -r --arg L "$NEW_LABEL" '.[]? | select(.label==$L and .value!="") | .value' | head -n1)
    [ -n "$VAL_ID" ] || fail "Fant ikke option for label \"$NEW_LABEL\" og kunne ikke opprette (HTTP $CREATE_CODE)."
  fi
fi

# 2) SKU: hvis tom, lag fra label (kun ASCII trygt)
if [ -z "${NEW_SKU:-}" ]; then
  SAFE=$(printf '%s' "$NEW_LABEL" | tr -cs '[:alnum:]' '-' | tr '[:lower:]' '[:upper:]')
  NEW_SKU="TEST-$SAFE"
fi

# 3) Upsert simple-produkt (POST->PUT)
POST_CODE=$(curl -sS -o /tmp/prod-create.json -w '%{http_code}' \
  -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data "$(jq -n \
    --arg sku "$NEW_SKU" \
    --arg name "$NEW_LABEL" \
    --arg attr "$ATTR_CODE" \
    --arg val "$VAL_ID" \
    --argjson set ${ATTR_SET_ID:-4} \
    --argjson wid ${WEBSITE_ID:-1} \
    '{product:{
      sku:$sku,name:$name,type_id:"simple",
      attribute_set_id:$set,visibility:1,price:399,status:1,weight:1,
      extension_attributes:{website_ids:[$wid]},
      custom_attributes:[{attribute_code:$attr,value:$val}]
    }}')" \
  "$BASE/rest/all/V1/products" || true)

if [ "$POST_CODE" = "200" ] || [ "$POST_CODE" = "201" ]; then
  :
else
  PUT_CODE=$(curl -sS -o /tmp/prod-put.json -w '%{http_code}' \
    -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data "$(jq -n \
      --arg sku "$NEW_SKU" \
      --arg name "$NEW_LABEL" \
      --arg attr "$ATTR_CODE" \
      --arg val "$VAL_ID" \
      --argjson set ${ATTR_SET_ID:-4} \
      --argjson wid ${WEBSITE_ID:-1} \
      '{product:{
        sku:$sku,name:$name,type_id:"simple",
        attribute_set_id:$set,visibility:1,price:399,status:1,weight:1,
        extension_attributes:{website_ids:[$wid]},
        custom_attributes:[{attribute_code:$attr,value:$val}]
      }}')" \
    "$BASE/rest/all/V1/products/$NEW_SKU" || true)
  [ "$PUT_CODE" = "200" ] || fail "PUT update feilet ($PUT_CODE): $(cat /tmp/prod-put.json || true)"
fi

# 4) MSI lager
STOCK_CODE=$(curl -sS -o /tmp/stock.json -w '%{http_code}' \
  -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data "$(jq -n \
    --arg sku "$NEW_SKU" \
    --arg src "${SOURCE_CODE:-default}" \
    --argjson qty ${NEW_QTY:-10} \
    '{sourceItems:[{sku:$sku,source_code:$src,quantity:$qty,status:1}]}' )" \
  "$BASE/rest/V1/inventory/source-items" || true)
case "$STOCK_CODE" in
  200|207) : ;;
  *) fail "Lager-feil ($STOCK_CODE): $(cat /tmp/stock.json || true)" ;;
esac

# 5) Parent option – sørg for at value_index finnes
# Les eksisterende option-id (om finnes)
OPT_JSON=$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/products/$PARENT_SKU?fields=extension_attributes" \
  | jq -c '.extension_attributes.configurable_product_options // []')
OPT_ID=$(printf '%s' "$OPT_JSON" | jq -r --arg code "$ATTR_CODE" '.[] | select(.label|tostring|ascii_downcase|contains("config") or .label==$code or .attribute_id!=null) | .id' | head -n1)

if [ -z "$OPT_ID" ] || [ "$OPT_ID" = "null" ]; then
  # Lag ny option for ATTR_CODE (krever attribute_id – hent den)
  ATTR_ID=$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/products/attributes/$ATTR_CODE" | jq -r '.attribute_id')
  [ -n "$ATTR_ID" ] || fail "Fant ikke attribute_id for $ATTR_CODE"
  PAYLOAD=$(jq -n --arg attr_id "$ATTR_ID" --arg label "$ATTR_CODE" \
    --argjson val "$VAL_ID" \
    '{option:{attribute_id:$attr_id,label:$label,position:0,is_use_default:true,values:[{value_index:$val}]}}')
  CREATE_OPT_CODE=$(curl -sS -o /tmp/opt.json -w '%{http_code}' \
    -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data-binary "$PAYLOAD" \
    "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/options" || true)
  [ "$CREATE_OPT_CODE" = "200" ] || [ "$CREATE_OPT_CODE" = "201" ] || fail "Opprette parent option feilet ($CREATE_OPT_CODE): $(cat /tmp/opt.json || true)"
else
  # Utvid eksisterende option med value_index om mangler
  CURR=$(printf '%s' "$OPT_JSON" | jq -c --arg id "$OPT_ID" '.[] | select(.id==($id|tonumber))')
  HAS=$(printf '%s' "$CURR" | jq -e --arg val "$VAL_ID" '.values[]? | select((.value_index|tostring)==$val)' >/dev/null 2>&1 || echo "no")
  if [ "$HAS" = "no" ]; then
    BODY=$(jq -n \
      --argjson id "$OPT_ID" \
      --arg attr_id "$(printf '%s' "$CURR" | jq -r '.attribute_id')" \
      --arg label    "$(printf '%s' "$CURR" | jq -r '.label')" \
      --argjson vals "$(printf '%s' "$CURR" | jq -c '.values')" \
      --argjson add  "$VAL_ID" \
      '{
        option:{
          id:$id, attribute_id:$attr_id, label:$label, position:0, is_use_default:true,
          values:($vals + [{value_index:$add}])
        }
      }')
    PUT_CODE=$(curl -sS -o /tmp/opt-put.json -w '%{http_code}' \
      -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data-binary "$BODY" \
      "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/options/\(echo "$OPT_ID")" || true)
    [ "$PUT_CODE" = "200" ] || fail "Oppdatere parent option feilet ($PUT_CODE): $(cat /tmp/opt-put.json || true)"
  fi
fi

# 6) Attach child
ATTACH_CODE=$(curl -sS -o /tmp/attach.json -w '%{http_code}' \
  -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data "$(jq -n --arg sku "$NEW_SKU" '{childSku:$sku}')" \
  "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/child" || true)
if [ "$ATTACH_CODE" = "200" ]; then : ; else
  if ! grep -q 'already attached' /tmp/attach.json 2>/dev/null; then
    fail "Attach feilet ($ATTACH_CODE): $(cat /tmp/attach.json || true)"
  fi
fi

# 7) Status
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
EOF
chmod +x add-color.sh

# --- variant-sync.sh ---------------------------------------------
cat > variant-sync.sh <<"EOF"
#!/usr/bin/env sh
set -eu

: "${BASE:?BASE not set}; ${AUTH_ADMIN:?AUTH_ADMIN not set}"
: "${PARENT_SKU:=TEST-CFG}"
: "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"
: "${SOURCE_CODE:=default}"
: "${ATTR_SET_ID:=4}"

echo "== Variant Auto-Healer =="
echo "BASE=$BASE  PARENT=$PARENT_SKU  ATTR=$ATTR_CODE  WEBSITE=$WEBSITE_ID"

# 1) Hent attribute_id og alle options
ATTR_ID=$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/products/attributes/$ATTR_CODE" | jq -r '.attribute_id')
OPTS=$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/products/attributes/$ATTR_CODE/options" \
  | jq -c '[.[] | select(.value!="")]')

# 2) Sørg for at parent har option for denne attributten (lag hvis mangler)
PARENT=$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/products/$PARENT_SKU?fields=extension_attributes")
CURR_OPT=$(printf '%s' "$PARENT" | jq -c '.extension_attributes.configurable_product_options // []')
OPT_ID=$(printf '%s' "$CURR_OPT" | jq -r --arg id "$ATTR_ID" '.[] | select(.attribute_id==$id or .label=="'"$ATTR_CODE"'") | .id' | head -n1)

if [ -z "$OPT_ID" ] || [ "$OPT_ID" = "null" ]; then
  DATA=$(jq -n --arg attr_id "$ATTR_ID" --arg label "$ATTR_CODE" \
    --argjson vals "$(printf '%s' "$OPTS" | jq '[.[] | {value_index:(.value|tonumber)}]')" \
    '{option:{attribute_id:$attr_id,label:$label,position:0,is_use_default:true,values:$vals}}')
  curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data-binary "$DATA" \
    "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/options" >/dev/null
else
  # Utvid med alle values som ikke finnes
  HAVE=$(printf '%s' "$CURR_OPT" | jq -c --argjson id "$OPT_ID" '.[] | select(.id==$id) | .values')
  NEED=$(jq -n \
    --argjson have "$HAVE" \
    --argjson want "$(printf '%s' "$OPTS" | jq '[.[] | {value_index:(.value|tonumber)}]')" \
    '$want - $have')
  if [ "$(printf '%s' "$NEED" | jq 'length')" -gt 0 ]; then
    BODY=$(jq -n \
      --argjson id "$OPT_ID" \
      --arg attr_id "$(printf '%s' "$CURR_OPT" | jq -r --argjson id "$OPT_ID" '.[] | select(.id==$id) | .attribute_id')" \
      --arg label    "$(printf '%s' "$CURR_OPT" | jq -r --argjson id "$OPT_ID" '.[] | select(.id==$id) | .label')" \
      --argjson vals "$(jq -n --argjson have "$HAVE" --argjson need "$NEED" '$have + $need')" \
      '{option:{id:$id,attribute_id:$attr_id,label:$label,position:0,is_use_default:true,values:$vals}}')
    curl -sS -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data-binary "$BODY" \
      "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/options/$(printf '%s' "$OPT_ID")" >/dev/null
  fi
fi

# 3) For hver option: sikre at SKU eksisterer, har riktig attribute, er på website, har MSI, og er attached
printf '%s' "$OPTS" | jq -rc '.[]' | while IFS= read -r row; do
  label=$(printf '%s' "$row" | jq -r '.label')
  val=$(printf '%s' "$row" | jq -r '.value')

  # Navn/sku forslag – vi gjør INGEN destructive endring hvis produkt finnes med annet navn
  SKU="TEST-$(printf '%s' "$label" | tr -cs '[:alnum:]' '-' | tr '[:lower:]' '[:upper:]')"

  echo "--- $SKU ($label → $val) ---"

  # Oppdater/lag produkt
  PUT=$(jq -n \
    --arg sku "$SKU" --arg name "$label" --arg attr "$ATTR_CODE" --arg val "$val" \
    --argjson set ${ATTR_SET_ID:-4} --argjson wid ${WEBSITE_ID:-1} \
    '{product:{sku:$sku,name:$name,type_id:"simple",attribute_set_id:$set,visibility:1,price:399,status:1,weight:1,
               extension_attributes:{website_ids:[$wid]},
               custom_attributes:[{attribute_code:$attr,value:$val}]}}')
  curl -sS -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data-binary "$PUT" \
    "$BASE/rest/all/V1/products/$SKU" >/dev/null 2>&1 || true

  # MSI
  curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data "$(jq -n --arg sku "$SKU" --arg src "${SOURCE_CODE:-default}" '{sourceItems:[{sku:$sku,source_code:$src,quantity:10,status:1}]}')" \
    "$BASE/rest/V1/inventory/source-items" >/dev/null 2>&1 || true

  # Attach
  curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data "$(jq -n --arg sku "$SKU" '{childSku:$sku}')" \
    "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/child" >/dev/null 2>&1 || true
done

echo "✅ Parent oppdatert."
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
EOF
chmod +x variant-sync.sh

# --- remove-color.sh ---------------------------------------------
cat > remove-color.sh <<"EOF"
#!/usr/bin/env sh
set -eu

: "${BASE:?BASE not set}; ${AUTH_ADMIN:?AUTH_ADMIN not set}"
: "${PARENT_SKU:=TEST-CFG}"

SKU="${1:-}"
[ -n "$SKU" ] || { echo "Bruk: ./remove-color.sh <child-sku>"; exit 1; }

# Fjern link (lar attribute option stå i fred)
curl -sS -X DELETE -H "$AUTH_ADMIN" \
  "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children/$SKU" \
  | jq . || true

# Status
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
EOF
chmod +x remove-color.sh

# --- slutt -------------------------------------------------------
echo "✅ Ferdig!"
echo "Kjør nå:  source ./.m2-env"
cat <<'EOT'
Eksempler:
  # Legg til ny variant (oppretter option hvis du har ACL; ellers slår opp eksisterende)
  NEW_LABEL=Purple NEW_SKU=TEST-PURPLE NEW_QTY=12 ./add-color.sh

  # Legg til variant ved å peke på eksisterende value_index (hopper over ACL behov):
  NEW_VAL_ID=7 NEW_LABEL=Blue NEW_SKU=TEST-BLUE-EXTRA NEW_QTY=5 ./add-color.sh

  # Auto-heal – lager manglende simple/stock/links for alle options:
  ./variant-sync.sh

  # Fjern en child fra parent (lar option stå):
  ./remove-color.sh TEST-PURPLE
EOT