#!/usr/bin/env sh
set -eu

say() { printf '%s\n' "$*" >&2; }

# ---- Inndata (les fra env eller prompt) ----
BASE="${BASE:-}"
ADMIN_USER="${ADMIN_USER:-}"
ADMIN_PASS="${ADMIN_PASS:-}"
PARENT_SKU="${PARENT_SKU:-TEST-CFG}"
ATTR_CODE="${ATTR_CODE:-cfg_color}"
WEBSITE_ID="${WEBSITE_ID:-1}"
SOURCE_CODE="${SOURCE_CODE:-default}"

if [ -z "$BASE" ]; then
  printf "BASE (f.eks. https://m2-dev.litebrygg.no): "
  IFS= read -r BASE
fi
BASE="${BASE%/}"

if [ -z "$ADMIN_USER" ]; then
  printf "ADMIN_USER: "
  IFS= read -r ADMIN_USER
fi
if [ -z "$ADMIN_PASS" ]; then
  printf "ADMIN_PASS: "
  stty -echo 2>/dev/null || true
  IFS= read -r ADMIN_PASS
  stty echo 2>/dev/null || true
  printf "\n"
fi

# ---- Hent admin-token ----
say "Henter admin token…"
TOKEN_RAW="$(curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
  -H 'Content-Type: application/json' \
  --data "{\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}")" || {
  say "❌ Klarte ikke å nå $BASE"; exit 1; }

# JSON-returnert token er en ren streng (JWT). Sjekk at det ser troverdig ut.
case "$TOKEN_RAW" in
  \"*\" ) M2_ADMIN_TOKEN=$(printf %s "$TOKEN_RAW" | sed -e 's/^"//' -e 's/"$//');;
  *.* )   M2_ADMIN_TOKEN="$TOKEN_RAW";;
  * )     say "❌ Ugyldig token-respons: $TOKEN_RAW"; exit 1;;
esac

AUTH_ADMIN="Authorization: Bearer ${M2_ADMIN_TOKEN}"
export BASE AUTH_ADMIN PARENT_SKU ATTR_CODE WEBSITE_ID SOURCE_CODE

say "✅ Token OK. BASE=$BASE  PARENT=$PARENT_SKU  ATTR=$ATTR_CODE  WEBSITE=$WEBSITE_ID  SOURCE=$SOURCE_CODE"

# ---- Røyktest ----
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/store/websites" >/dev/null \
  && say "✅ REST svarer." || { say "❌ Auth/URL feilet."; exit 1; }

# ---- add-color.sh ----
cat > add-color.sh <<'ADD'
#!/usr/bin/env sh
set -eu
: "${BASE:?BASE not set}"
: "${AUTH_ADMIN:?AUTH_ADMIN not set}"
PARENT_SKU="${PARENT_SKU:-TEST-CFG}"
ATTR_CODE="${ATTR_CODE:-cfg_color}"
WEBSITE_ID="${WEBSITE_ID:-1}"
SOURCE_CODE="${SOURCE_CODE:-default}"
NEW_LABEL="${NEW_LABEL:-Purple}"
NEW_SKU="${NEW_SKU:-TEST-PURPLE}"
NEW_QTY="${NEW_QTY:-5}"

# 1) Attributt
RESP="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/products/attributes/$ATTR_CODE")"
ATTR_ID="$(printf '%s' "$RESP" | jq -r '.attribute_id // empty')"
[ -n "$ATTR_ID" ] || { echo "❌ fant ikke attribute_id for $ATTR_CODE"; exit 1; }

# 2) Option-verdi
VAL_ID="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/products/attributes/$ATTR_CODE/options" \
  | jq -r --arg L "$NEW_LABEL" '.[]? | select(.label==$L) | .value // empty')"
if [ -z "$VAL_ID" ] || [ "$VAL_ID" = "null" ]; then
  VAL_ID="$(curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data "{\"option\":{\"label\":\"${NEW_LABEL}\",\"sort_order\":99,\"is_default\":false}}" \
    "$BASE/rest/V1/products/attributes/$ATTR_CODE/options" | jq -r '.')"
fi
[ -n "$VAL_ID" ] && [ "$VAL_ID" != "null" ] || { echo "❌ klarte ikke lage option-verdi"; exit 1; }

# 3) Simple-produkt
curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data "{\"product\":{\"sku\":\"${NEW_SKU}\",\"name\":\"${NEW_LABEL}\",\"type_id\":\"simple\",\"attribute_set_id\":4,\"price\":399,\"status\":1,\"visibility\":1,\"weight\":1,\"extension_attributes\":{\"website_ids\":[${WEBSITE_ID}]},\"custom_attributes\":[{\"attribute_code\":\"${ATTR_CODE}\",\"value\":\"${VAL_ID}\"}]}}" \
  "$BASE/rest/all/V1/products" >/dev/null 2>&1 || true

# 3b) MSI
curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data "{\"sourceItems\":[{\"sku\":\"${NEW_SKU}\",\"source_code\":\"${SOURCE_CODE}\",\"quantity\":${NEW_QTY},\"status\":1}]}" \
  "$BASE/rest/V1/inventory/source-items" >/dev/null 2>&1 || true

# 4) Configurable option på parent
OPT_JSON="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/products/$PARENT_SKU?fields=extension_attributes")"
PARENT_OPT_ID="$(printf '%s' "$OPT_JSON" | jq -r --arg id "$ATTR_ID" '.extension_attributes.configurable_product_options[]? | select(.attribute_id==$id) | .id' | head -n1)"
if [ -z "$PARENT_OPT_ID" ] || [ "$PARENT_OPT_ID" = "null" ]; then
  DATA_OPT="$(jq -n --arg attr_id "$ATTR_ID" --arg label "$ATTR_CODE" --argjson val "$VAL_ID" \
    '{option:{attribute_id:$attr_id,label:$label,position:0,is_use_default:true,values:[{value_index:$val}]}}')"
  curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    --data-binary "$DATA_OPT" \
    "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/options" >/dev/null
else
  CUR_VALS="$(printf '%s' "$OPT_JSON" | jq -r --arg id "$ATTR_ID" '.extension_attributes.configurable_product_options[]?|select(.attribute_id==$id)|.values[]?.value_index' | sort -n | uniq)"
  echo "$CUR_VALS" | grep -qx "$VAL_ID" || {
    NEW_VALS="$(printf '%s\n%s\n' "$CUR_VALS" "$VAL_ID" | awk 'NF' | sort -n | uniq | jq -Rsn '[inputs|tonumber]')"
    DATA_UPD="$(jq -n --arg id "$PARENT_OPT_ID" --arg attr_id "$ATTR_ID" --arg label "$ATTR_CODE" --argjson arr "$NEW_VALS" \
      '{option:{id:($id|tonumber),attribute_id:$attr_id,label:$label,position:0,is_use_default:true,values:($arr|map({value_index:.}))}}')"
    curl -sS -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data-binary "$DATA_UPD" \
      "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/options/$PARENT_OPT_ID" >/dev/null
  }
fi

# 5) Attach
curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data "{\"childSku\":\"${NEW_SKU}\"}" \
  "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/child" >/dev/null 2>&1 || true

# Status
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
ADD
chmod +x add-color.sh

# ---- remove-color.sh ----
cat > remove-color.sh <<'REM'
#!/usr/bin/env sh
set -eu
: "${BASE:?BASE not set}"
: "${AUTH_ADMIN:?AUTH_ADMIN not set}"
PARENT_SKU="${PARENT_SKU:-TEST-CFG}"
ATTR_CODE="${ATTR_CODE:-cfg_color}"
SKU="${1:?Usage: remove-color.sh <SKU>}"

# 1) Detach child
curl -sS -X DELETE -H "$AUTH_ADMIN" \
  "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children/$SKU" >/dev/null 2>&1 || true

# 2) Finn value_id
VAL_ID="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/default/V1/products/$SKU?fields=sku,custom_attributes" \
  | jq -r --arg code "$ATTR_CODE" '.custom_attributes[]? | select(.attribute_code==$code) | .value // empty')"

# 3) Sett lager=0 og status=0
curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data "{\"sourceItems\":[{\"sku\":\"${SKU}\",\"source_code\":\"default\",\"quantity\":0,\"status\":0}]}" \
  "$BASE/rest/V1/inventory/source-items" >/dev/null 2>&1 || true

# 4) Fjern option-verdi fra parent hvis ubrukt
if [ -n "$VAL_ID" ]; then
  ATTR_ID="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/products/attributes/$ATTR_CODE" | jq -r '.attribute_id')"
  OPT_JSON="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/products/$PARENT_SKU?fields=extension_attributes")"
  PARENT_OPT_ID="$(printf '%s' "$OPT_JSON" | jq -r --arg id "$ATTR_ID" '.extension_attributes.configurable_product_options[]? | select(.attribute_id==$id) | .id' | head -n1)"

  IN_USE="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children" \
    | jq -r '.[].sku' \
    | while IFS= read -r s; do
        curl -sS -H "$AUTH_ADMIN" "$BASE/rest/default/V1/products/$s?fields=sku,custom_attributes" \
        | jq -r --arg code "$ATTR_CODE" --arg val "$VAL_ID" ' .custom_attributes[]? | select(.attribute_code==$code and .value==$val) | "hit" ';
      done | wc -l | tr -d ' ')"

  if [ "$IN_USE" = "0" ] && [ -n "$PARENT_OPT_ID" ] && [ "$PARENT_OPT_ID" != "null" ]; then
    CUR_VALS="$(printf '%s' "$OPT_JSON" | jq -r --arg id "$ATTR_ID" '.extension_attributes.configurable_product_options[]?|select(.attribute_id==$id)|.values[]?.value_index')"
    NEW_VALS="$(printf '%s\n' "$CUR_VALS" | grep -v -x "$VAL_ID" | awk 'NF' | sort -n | uniq | jq -Rsn '[inputs|tonumber]')"
    DATA_UPD="$(jq -n --arg id "$PARENT_OPT_ID" --arg attr_id "$ATTR_ID" --arg label "$ATTR_CODE" --argjson arr "$NEW_VALS" \
      '{option:{id:($id|tonumber),attribute_id:$attr_id,label:$label,position:0,is_use_default:true,values:($arr|map({value_index:.}))}}')"
    curl -sS -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data-binary "$DATA_UPD" \
      "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/options/$PARENT_OPT_ID" >/dev/null 2>&1 || true
  fi
fi

# Sluttstatus
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
REM
chmod +x remove-color.sh

# ---- variant-sync.sh ----
cat > variant-sync.sh <<'SYNC'
#!/usr/bin/env sh
set -eu
: "${BASE:?BASE not set}"
: "${AUTH_ADMIN:?AUTH_ADMIN not set}"
PARENT_SKU="${PARENT_SKU:-TEST-CFG}"
ATTR_CODE="${ATTR_CODE:-cfg_color}"
WEBSITE_ID="${WEBSITE_ID:-1}"
SOURCE_CODE="${SOURCE_CODE:-default}"

echo "== Variant Auto-Healer =="
echo "BASE=$BASE  PARENT=$PARENT_SKU  ATTR=$ATTR_CODE  WEBSITE=$WEBSITE_ID"

RESP="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/products/attributes/$ATTR_CODE")"
ATTR_ID="$(printf '%s' "$RESP" | jq -r '.attribute_id')"

OPTS="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/products/attributes/$ATTR_CODE/options")"
CHILDREN="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children" | jq -r '.[].sku')"

P_OPT_JSON="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/products/$PARENT_SKU?fields=extension_attributes")"
PARENT_OPT_ID="$(printf '%s' "$P_OPT_JSON" | jq -r --arg id "$ATTR_ID" '.extension_attributes.configurable_product_options[]? | select(.attribute_id==$id) | .id' | head -n1)"
if [ -z "$PARENT_OPT_ID" ] || [ "$PARENT_OPT_ID" = "null" ]; then
  INIT="$(jq -n --arg attr_id "$ATTR_ID" --arg label "$ATTR_CODE" '{option:{attribute_id:$attr_id,label:$label,position:0,is_use_default:true,values:[]}}')"
  curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' --data-binary "$INIT" \
    "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/options" >/dev/null
  P_OPT_JSON="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/products/$PARENT_SKU?fields=extension_attributes")"
  PARENT_OPT_ID="$(printf '%s' "$P_OPT_JSON" | jq -r --arg id "$ATTR_ID" '.extension_attributes.configurable_product_options[]? | select(.attribute_id==$id) | .id' | head -n1)"
fi

printf '%s' "$OPTS" | jq -r '.[]? | select(.value!="") | @base64' | while IFS= read -r row; do
  label="$(printf '%s' "$row" | base64 -d | jq -r '.label')"
  val="$(printf  '%s' "$row" | base64 -d | jq -r '.value')"
  up="$(printf '%s' "$label" | tr '[:lower:]' '[:upper:]' | tr -cs 'A-Z0-9' '-' | sed -E 's/^-+|-+$//g; s/-{2,}/-/g')"
  sku="TEST-$up"
  echo "--- $sku ($label → $val) ---"

  echo "$CHILDREN" | grep -Fxq "$sku" || {
    curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data "{\"product\":{\"sku\":\"${sku}\",\"name\":\"${label}\",\"type_id\":\"simple\",\"attribute_set_id\":4,\"price\":399,\"status\":1,\"visibility\":1,\"weight\":1,\"extension_attributes\":{\"website_ids\":[${WEBSITE_ID}]},\"custom_attributes\":[{\"attribute_code\":\"${ATTR_CODE}\",\"value\":\"${val}\"}]}}" \
      "$BASE/rest/all/V1/products" >/dev/null 2>&1 || true
    curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data "{\"sourceItems\":[{\"sku\":\"${sku}\",\"source_code\":\"${SOURCE_CODE}\",\"quantity\":5,\"status\":1}]}" \
      "$BASE/rest/V1/inventory/source-items" >/dev/null 2>&1 || true
    curl -sS -X POST -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data "{\"childSku\":\"${sku}\"}" \
      "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/child" >/dev/null 2>&1 || true
  }

  CUR_VALS="$(printf '%s' "$P_OPT_JSON" | jq -r --arg id "$ATTR_ID" '.extension_attributes.configurable_product_options[]?|select(.attribute_id==$id)|.values[]?.value_index' | sort -n | uniq)"
  echo "$CUR_VALS" | grep -qx "$val" || {
    NEW_VALS="$(printf '%s\n%s\n' "$CUR_VALS" "$val" | awk 'NF' | sort -n | uniq | jq -Rsn '[inputs|tonumber]')"
    DATA_UPD="$(jq -n --arg id "$PARENT_OPT_ID" --arg attr_id "$ATTR_ID" --arg label "$ATTR_CODE" --argjson arr "$NEW_VALS" \
      '{option:{id:($id|tonumber),attribute_id:$attr_id,label:$label,position:0,is_use_default:true,values:($arr|map({value_index:.}))}}')"
    curl -sS -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
      --data-binary "$DATA_UPD" \
      "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/options/$PARENT_OPT_ID" >/dev/null
    P_OPT_JSON="$(curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/products/$PARENT_SKU?fields=extension_attributes")"
  }
done

echo "✅ Parent oppdatert."
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
SYNC
chmod +x variant-sync.sh

say "✅ Ferdig! Tilgjengelige kommandoer:"
say "  NEW_LABEL=Purple NEW_SKU=TEST-PURPLE NEW_QTY=12 ./add-color.sh"
say "  ./variant-sync.sh"
say "  ./remove-color.sh TEST-PURPLE"

# Mini-sjekk
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/all/V1/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)' || true

# --- auto-write .m2-env for reuse ---
printf "export BASE=%q\n" "$BASE"   > .m2-env
printf "export AUTH_ADMIN=%q\n" "$AUTH_ADMIN" >> .m2-env
printf "export PARENT_SKU=%q\n" "$PARENT_SKU" >> .m2-env
printf "export ATTR_CODE=%q\n" "$ATTR_CODE" >> .m2-env
printf "export WEBSITE_ID=%q\n" "$WEBSITE_ID" >> .m2-env
printf "export SOURCE_CODE=%q\n" "$SOURCE_CODE" >> .m2-env
echo "Tip: kjør \"source ./.m2-env\" før helper-skriptene."
