#!/usr/bin/env bash
set -euo pipefail

echo "== Magento Variant Autoinstaller =="
# --- 1) Spør om BASE + admin creds (med defaults om funnet fra miljø)
read -rp "BASE (f.eks. https://m2-dev.litebrygg.no): " BASE_IN
BASE="${BASE_IN%/}"
[ -z "${BASE}" ] && { echo "BASE er påkrevd"; exit 1; }

read -rp "ADMIN_USER: " ADMIN_USER
stty -echo 2>/dev/null || true
read -rp "ADMIN_PASS: " ADMIN_PASS; echo
stty echo 2>/dev/null || true
[ -z "${ADMIN_USER}" ] && { echo "ADMIN_USER mangler"; exit 1; }
[ -z "${ADMIN_PASS}" ] && { echo "ADMIN_PASS mangler"; exit 1; }

# --- 2) Hent token
echo "Henter admin token…"
ADMIN_TOKEN=$(
  curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
  | sed -e 's/^"//' -e 's/"$//'
)
if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
  echo "Kunne ikke hente token"; exit 1
fi
AUTH_ADMIN="Authorization: Bearer $ADMIN_TOKEN"

# --- 3) Skriv .m2-env (trygt sitert + newline)
cat > .m2-env <<ENV
export BASE='$BASE'
export AUTH_ADMIN='Authorization: Bearer $ADMIN_TOKEN'
export PARENT_SKU='TEST-CFG'
export ATTR_CODE='cfg_color'
export WEBSITE_ID='1'
export SOURCE_CODE='default'

# Preferred REST bases
export READ_BASE="\$BASE/rest/all/V1"   # GET
export WRITE_BASE="\$BASE/rest/V1"      # POST/PUT/DELETE

# For auto-refresh
export ADMIN_USER='$ADMIN_USER'
export ADMIN_PASS='$ADMIN_PASS'
ENV

# --- 4) Små sanity-checks
echo "Tester REST…"
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/store/websites" >/dev/null
echo "✅ REST svarer."

# --- 5) Lag/overskriv robuste helper-skript (backup først)
backup() { [ -f "$1" ] && cp -f "$1" "$1.bak.$(date +%s)" || true; }

# --- Felles bibliotek .m2-lib.sh (do_write + refresh)
backup ".m2-lib.sh"
cat > .m2-lib.sh <<'LIB'
#!/usr/bin/env bash
set -euo pipefail
: "${READ_BASE:="$BASE/rest/all/V1"}"
: "${WRITE_BASE:="$BASE/rest/V1"}"

refresh_token_if_needed() {
  local code="${1:-}"; [ "$code" != "401" ] && return 0
  [ -z "${ADMIN_USER:-}" ] && return 0
  [ -z "${ADMIN_PASS:-}" ] && return 0
  local new
  new=$(curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
           -H 'Content-Type: application/json' \
           --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
         | sed -e 's/^"//' -e 's/"$//')
  [ -n "$new" ] && export AUTH_ADMIN="Authorization: Bearer $new"
}

# do_write METHOD URL JSON -> prints body, returns 0 on 2xx
do_write() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1:-}"
  local resp code body
  resp=$(curl -sS -w '\n%{http_code}' -X "$method" \
            -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
            ${data:+--data "$data"} "$url")
  code=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')
  refresh_token_if_needed "$code"
  if [ "$code" = "401" ]; then
    resp=$(curl -sS -w '\n%{http_code}' -X "$method" \
              -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
              ${data:+--data "$data"} "$url")
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
  fi
  if [[ "$code" =~ ^2 ]]; then
    printf '%s' "$body"
    return 0
  fi
  echo "$body" >&2
  return 1
}
LIB
chmod +x .m2-lib.sh

# --- add-color.sh (robust)
backup "add-color.sh"
cat > add-color.sh <<'ADD'
#!/usr/bin/env bash
set -euo pipefail
source ./.m2-env
source ./.m2-lib.sh
: "${PARENT_SKU:=TEST-CFG}"
: "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"
: "${SOURCE_CODE:=default}"

NEW_LABEL="${NEW_LABEL:-}"
NEW_VAL_ID="${NEW_VAL_ID:-}"
NEW_SKU="${NEW_SKU:-}"
NEW_QTY="${NEW_QTY:-5}"
[ -z "$NEW_SKU" ] && { echo "NEW_SKU er påkrevd"; exit 1; }

# 1) Finn attr id
CFG_ATTR_ID=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE" | jq -r '.attribute_id')
[ -z "$CFG_ATTR_ID" ] || [ "$CFG_ATTR_ID" = "null" ] && { echo "Fant ikke attribute $ATTR_CODE"; exit 1; }

# 2) Finn/lag option verdi
VAL_ID="$NEW_VAL_ID"
if [ -z "$VAL_ID" ]; then
  if [ -n "$NEW_LABEL" ]; then
    # Prøv å opprette (kan feile på ACL)
    set +e
    CREATED=$(do_write POST "$WRITE_BASE/products/attributes/$ATTR_CODE/options" \
      "$(jq -c --arg l "$NEW_LABEL" '{option:{label:$l,sort_order:99,is_default:false}}')")
    ok=$?
    set -e
    if [ $ok -eq 0 ]; then
      VAL_ID=$(echo "$CREATED" | jq -r '. // empty')
    fi
  fi
  # Lookup uansett (case-insensitive)
  OPTS=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE/options")
  if [ -z "${VAL_ID:-}" ] || [ "$VAL_ID" = "null" ]; then
    VAL_ID=$(jq -r --arg l "${NEW_LABEL:-}" '
      map(select(.value != "")) |
      ( .[] | select((.label|ascii_downcase) == ($l|ascii_downcase)) | .value ) // empty
    ' <<<"$OPTS")
  fi
fi
[ -z "${VAL_ID:-}" ] && { echo "❌ Fant ikke/kunne ikke opprette option for label \"$NEW_LABEL\""; exit 1; }

# 3) Lag/fiks simple
PAYLOAD=$(jq -c --arg sku "$NEW_SKU" --argjson set 4 --argjson wid "$WEBSITE_ID" --arg val "$VAL_ID" '
  { product:{
      sku:$sku, name:$sku, type_id:"simple",
      attribute_set_id:$set, visibility:1, price:399, status:1, weight:1,
      extension_attributes:{ website_ids:[$wid] },
      custom_attributes:[ {attribute_code:"'${ATTR_CODE}'", value:$val} ]
    } }')
set +e
RES=$(do_write POST "$WRITE_BASE/products" "$PAYLOAD")
ok=$?; set -e
if [ $ok -ne 0 ]; then
  # Prøv PUT (eksisterer fra før)
  RES=$(do_write PUT "$WRITE_BASE/products/$NEW_SKU" "$PAYLOAD")
fi

# 3b) MSI
do_write POST "$WRITE_BASE/inventory/source-items" \
  "$(jq -c --arg sku "$NEW_SKU" --arg src "$SOURCE_CODE" --argjson qty "$NEW_QTY" \
     '{sourceItems:[{sku:$sku,source_code:$src,quantity:$qty,status:1}]}' )" >/dev/null || true

# 4) Sørg for at parent har option for attribute + verdi
PARENT=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes")
OPT_ID=$(jq -r --arg id "$CFG_ATTR_ID" '.extension_attributes.configurable_product_options[]? | select(.attribute_id==$id) | .id' <<<"$PARENT")
if [ -z "$OPT_ID" ]; then
  # Opprett option
  do_write POST "$WRITE_BASE/configurable-products/$PARENT_SKU/options" \
    "$(jq -c --arg id "$CFG_ATTR_ID" --arg l "$ATTR_CODE" --argjson vi "$VAL_ID" \
      '{option:{attribute_id:$id,label:$l,position:0,is_use_default:true,values:[{value_index:$vi}]}}' )" >/dev/null
else
  # Oppdater values (legg til hvis mangler)
  CURR=$(jq -c --arg id "$CFG_ATTR_ID" '
    .extension_attributes.configurable_product_options[] |
    select(.attribute_id==$id) | .values | map(.value_index)
  ' <<<"$PARENT")
  ADD=$(jq -r --argjson vi "$VAL_ID" --argjson arr "$CURR" '([ $vi ] - $arr) | length' <<<"{}")
  if [ "$ADD" != "0" ]; then
    NEWVALS=$(jq -c --argjson vi "$VAL_ID" --argjson arr "$CURR" \
      '($arr + [ $vi ]) | unique | map({value_index:.})' <<<"{}")
    do_write PUT "$WRITE_BASE/configurable-products/$PARENT_SKU/options/$OPT_ID" \
      "$(jq -c --argjson oid "$OPT_ID" --arg id "$CFG_ATTR_ID" --arg l "$ATTR_CODE" --argjson vals "$NEWVALS" \
        '{option:{id:$oid,attribute_id:$id,label:$l,position:0,is_use_default:true,values:$vals}}' )" >/dev/null
  fi
fi

# 5) Attach child
do_write POST "$WRITE_BASE/configurable-products/$PARENT_SKU/child" \
  "$(jq -c --arg sku "$NEW_SKU" '{childSku:$sku}')" >/dev/null || true

# 6) Vis status
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
ADD
chmod +x add-color.sh

# --- remove-color.sh
backup "remove-color.sh"
cat > remove-color.sh <<'REM'
#!/usr/bin/env bash
set -euo pipefail
source ./.m2-env
source ./.m2-lib.sh
: "${PARENT_SKU:=TEST-CFG}"

SKU="${1:-}"
[ -z "$SKU" ] && { echo "Bruk: ./remove-color.sh <child-sku>"; exit 1; }

# Detach child (lar attribute option stå i fred)
set +e
OUT=$(do_write DELETE "$WRITE_BASE/configurable-products/$PARENT_SKU/children/$SKU" "")
ok=$?
set -e
if [ $ok -ne 0 ]; then
  echo "$OUT" >&2
fi

# Vis status
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
REM
chmod +x remove-color.sh

# --- variant-sync.sh (relinker/fornyer option-verdier på parent basert på eksisterende)
backup "variant-sync.sh"
cat > variant-sync.sh <<'SYNC'
#!/usr/bin/env bash
set -euo pipefail
source ./.m2-env
source ./.m2-lib.sh
: "${PARENT_SKU:=TEST-CFG}"
: "${ATTR_CODE:=cfg_color}"

echo "== Variant Auto-Healer =="
echo "BASE=$BASE  PARENT=$PARENT_SKU  ATTR=$ATTR_CODE  WEBSITE=${WEBSITE_ID:-?}"

# Finn attribute-id + options
ATTR=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE")
CFG_ATTR_ID=$(jq -r '.attribute_id' <<<"$ATTR")
[ -z "$CFG_ATTR_ID" ] || [ "$CFG_ATTR_ID" = "null" ] && { echo "Fant ikke attribute $ATTR_CODE"; exit 1; }
OPTS=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/attributes/$ATTR_CODE/options" | jq -c 'map(select(.value!=""))')

# Finn eksisterende children
CHILDREN=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -r '.[].sku')

# Sørg for at parent har configurable option
PARENT=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes")
OPT_ID=$(jq -r --arg id "$CFG_ATTR_ID" '.extension_attributes.configurable_product_options[]? | select(.attribute_id==$id) | .id' <<<"$PARENT")
if [ -z "$OPT_ID" ]; then
  # opprett tom option med alle verdier
  VALUES=$(jq -c 'map({value_index:.value|tonumber})' <<<"$OPTS")
  do_write POST "$WRITE_BASE/configurable-products/$PARENT_SKU/options" \
    "$(jq -c --arg id "$CFG_ATTR_ID" --arg l "$ATTR_CODE" --argjson vals "$VALUES" '{option:{attribute_id:$id,label:$l,position:0,is_use_default:true,values:$vals}}')" >/dev/null
else
  CURR=$(jq -c --arg id "$CFG_ATTR_ID" '.extension_attributes.configurable_product_options[] | select(.attribute_id==$id) | .values | map(.value_index)' <<<"$PARENT")
  ALL=$(jq -c 'map(.value|tonumber)' <<<"$OPTS")
  NEWVALS=$(jq -c --argjson a "$ALL" --argjson c "$CURR" '((c+a)|unique) | map({value_index:.})' <<<"{}")
  do_write PUT "$WRITE_BASE/configurable-products/$PARENT_SKU/options/$OPT_ID" \
    "$(jq -c --argjson oid "$OPT_ID" --arg id "$CFG_ATTR_ID" --arg l "$ATTR_CODE" --argjson vals "$NEWVALS" '{option:{id:$oid,attribute_id:$id,label:$l,position:0,is_use_default:true,values:$vals}}')" >/dev/null
fi

echo "✅ Parent oppdatert."
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
SYNC
chmod +x variant-sync.sh

echo "✅ Ferdig! Kjør:  source ./.m2-env"
echo "Eksempler:"
echo "  NEW_VAL_ID=7 NEW_LABEL=Blue NEW_SKU=TEST-BLUE-EXTRA NEW_QTY=5 ./add-color.sh"
echo "  NEW_LABEL=Purple NEW_SKU=TEST-PURPLE NEW_QTY=12 ./add-color.sh"
echo "  ./variant-sync.sh"
echo "  ./remove-color.sh TEST-PURPLE"