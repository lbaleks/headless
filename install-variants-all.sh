#!/usr/bin/env bash
set -euo pipefail

# ---------- 1) INPUTS ----------
read -rp "BASE (f.eks. https://m2-dev.litebrygg.no): " BASE_RAW
BASE="${BASE_RAW%%[[:space:]]*}"; BASE="${BASE%%#*}"; BASE="${BASE%/}"
case "$BASE" in http://*|https://*) ;; *) echo "Ugyldig BASE: $BASE"; exit 1;; esac

if [ -z "${ADMIN_USER:-}" ]; then read -rp "ADMIN_USER: " ADMIN_USER; else echo "ADMIN_USER: $ADMIN_USER"; fi
if [ -z "${ADMIN_PASS:-}" ]; then stty -echo 2>/dev/null || true; read -rp "ADMIN_PASS: " ADMIN_PASS; echo; stty echo 2>/dev/null || true; fi
: "${ADMIN_USER:?}"; : "${ADMIN_PASS:?}"

PARENT_SKU="${PARENT_SKU:-TEST-CFG}"
ATTR_CODE="${ATTR_CODE:-cfg_color}"
WEBSITE_ID="${WEBSITE_ID:-1}"
SOURCE_CODE="${SOURCE_CODE:-default}"
READ_BASE="$BASE/rest/all/V1"
WRITE_BASE="$BASE/rest/V1"

# ---------- 2) TOKEN HENTING/REFRESH ----------
get_token() {
  curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
  | sed -e 's/^"//' -e 's/"$//'
}

ADMIN_TOKEN="$(get_token)"
AUTH_ADMIN="Authorization: Bearer $ADMIN_TOKEN"

refresh_token() {
  local new; new="$(get_token || true)"
  if [ -n "$new" ] && [ "$new" != "$ADMIN_TOKEN" ]; then
    ADMIN_TOKEN="$new"
    AUTH_ADMIN="Authorization: Bearer $ADMIN_TOKEN"
    # oppdater .m2-env også
    perl -pi -e "s|^(export AUTH_ADMIN=).*|\$1'Authorization: Bearer $ADMIN_TOKEN'|g" .m2-env 2>/dev/null || true
  fi
}

# ---------- 3) SAFE CURL ----------
safe_curl_tpl='
safe_curl() {
  # usage: safe_curl GET|POST|PUT|DELETE url [json_data]
  local method="$1" url="$2" data="${3:-}" code tmp
  tmp="$(mktemp -t m2resp.XXXXXX)"
  if [ -n "$data" ]; then
    code="$(curl -sS --max-time 25 --retry 1 -X "$method" -H "$AUTH_ADMIN" -H "Content-Type: application/json" --data-binary "$data" "$url" -o "$tmp" -w "%{http_code}")"
  else
    code="$(curl -sS --max-time 25 --retry 1 -X "$method" -H "$AUTH_ADMIN" "$url" -o "$tmp" -w "%{http_code}")"
  fi
  if [ "$code" = "401" ] || [ "$code" = "403" ]; then
    refresh_token 2>/dev/null || true
    if [ -n "$data" ]; then
      code="$(curl -sS --max-time 25 --retry 1 -X "$method" -H "$AUTH_ADMIN" -H "Content-Type: application/json" --data-binary "$data" "$url" -o "$tmp" -w "%{http_code}")"
    else
      code="$(curl -sS --max-time 25 --retry 1 -X "$method" -H "$AUTH_ADMIN" "$url" -o "$tmp" -w "%{http_code}")"
    fi
  fi
  if [ "$code" != "200" ] && [ "$code" != "201" ]; then
    echo "❌ HTTP $code $method $url" >&2
    printf "↳ body head: %s\n" "$(head -c 300 "$tmp")" >&2
    rm -f "$tmp"
    exit 1
  fi
  cat "$tmp"
  rm -f "$tmp"
}
'

# ---------- 4) SKRIV .m2-env ----------
cat > .m2-env <<ENV
export BASE='$BASE'
export AUTH_ADMIN='Authorization: Bearer $ADMIN_TOKEN'
export PARENT_SKU='$PARENT_SKU'
export ATTR_CODE='$ATTR_CODE'
export WEBSITE_ID='$WEBSITE_ID'
export SOURCE_CODE='$SOURCE_CODE'
export READ_BASE="$READ_BASE"
export WRITE_BASE="$WRITE_BASE"
export ADMIN_USER='$ADMIN_USER'
export ADMIN_PASS='$ADMIN_PASS'
ENV

# ---------- 5) SKRIV SCRIPT: variant-sync.sh ----------
cat > variant-sync.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"
: "${PARENT_SKU:=TEST-CFG}"; : "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"; : "${SOURCE_CODE:=default}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"
: "${ADMIN_USER:=}"; : "${ADMIN_PASS:=}"

refresh_token() {
  [ -z "${ADMIN_USER:-}" ] && return 0
  [ -z "${ADMIN_PASS:-}" ] && return 0
  local new
  new="$(curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
    | sed -e 's/^\"//' -e 's/\"$//')" || true
  if [ -n "$new" ] && [ "$new" != "${AUTH_ADMIN#Authorization: Bearer }" ]; then
    AUTH_ADMIN="Authorization: Bearer $new"
  fi
}
SAFE_CURL_PLACEHOLDER

say(){ printf '%s\n' "$*"; }
sku_from_label(){ printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr ' ' '-' | tr -cd 'A-Z0-9-_'; }

say "== Variant Auto-Healer =="
say "BASE=$BASE  PARENT=$PARENT_SKU  ATTR=$ATTR_CODE  WEBSITE=$WEBSITE_ID"

attr_json="$(safe_curl GET "$READ_BASE/products/attributes/$ATTR_CODE")"
attr_id="$(printf '%s' "$attr_json" | jq -r '.attribute_id')"
[ -n "$attr_id" ] || { echo "❌ Fant ikke attribute $ATTR_CODE"; exit 1; }

opts="$(safe_curl GET "$READ_BASE/products/attributes/$ATTR_CODE/options" \
  | jq -c '[.[] | select(.value != "") | {value: (try (.value|tonumber) // empty), label}]')"
printf '%s' "$opts" | jq -e . >/dev/null || { echo "❌ Feil ved lesing av options"; exit 1; }

children="$(safe_curl GET "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -r '.[].sku' || true)"
say "Current children:"; printf '%s\n' "${children:-}" | sed '/^$/d' || true

want_vals="$(printf '%s' "$opts" | jq -c '[.[].value | select(.!=null)] // []')"

parent_opt_id="$(safe_curl GET "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes" \
 | jq -r --arg id "$attr_id" '
   .extension_attributes.configurable_product_options // []
   | map(select(.attribute_id==$id)) | .[0].id // empty')"

if [ -z "$parent_opt_id" ] || [ "$parent_opt_id" = "null" ]; then
  data="$(jq -n --arg id "$attr_id" --arg label "$ATTR_CODE" --argjson vals "$want_vals" \
   '{option:{attribute_id:$id,label:$label,position:0,is_use_default:true,values:($vals|map({value_index:.}))}}')"
  safe_curl POST "$WRITE_BASE/configurable-products/$PARENT_SKU/options" "$data" >/dev/null
else
  have_vals="$(safe_curl GET "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes" \
    | jq -c --arg id "$attr_id" '
      .extension_attributes.configurable_product_options // []
      | map(select(.attribute_id==$id)) | .[0].values // [] | map(.value_index) // []')"
  merged="$(jq -c --argjson a "$have_vals" --argjson c "$want_vals" '($a + $c) | unique')"
  real_id="$parent_opt_id"
  data="$(jq -n --arg id "$attr_id" --argjson vals "$merged" \
     '{option:{attribute_id:$id,label:"Config Color",position:0,is_use_default:true,values:($vals|map({value_index:.}))}}')"
  safe_curl PUT "$WRITE_BASE/configurable-products/$PARENT_SKU/options/$real_id" "$data" >/dev/null
fi

printf '%s' "$opts" | jq -c '.[]' | while IFS= read -r row; do
  val="$(printf '%s' "$row" | jq -r '.value')"
  label="$(printf '%s' "$row" | jq -r '.label')"
  [ -n "$val" ] || continue
  sku="TEST-$(sku_from_label "$label")"
  name="TEST $label"

  if ! printf '%s\n' "${children:-}" | grep -qx "$sku"; then
    body="$(jq -n --arg sku "$sku" --arg name "$name" --argjson val "$val" --argjson wid "$WEBSITE_ID" \
      '{product:{sku:$sku,name:$name,type_id:"simple",attribute_set_id:4,visibility:1,price:399,status:1,weight:1,
                 extension_attributes:{website_ids:[$wid]},
                 custom_attributes:[{attribute_code:"'"$ATTR_CODE"'",value:$val}]}}')"
    safe_curl POST "$WRITE_BASE/products" "$body" >/dev/null || true

    stock="$(jq -n --arg sku "$sku" \
      '{sourceItems:[{sku:$sku,source_code:"'"$SOURCE_CODE"'",quantity:5,status:1}]}' )"
    safe_curl POST "$WRITE_BASE/inventory/source-items" "$stock" >/dev/null || true

    safe_curl POST "$WRITE_BASE/configurable-products/$PARENT_SKU/child" "{\"childSku\":\"$sku\"}" >/dev/null || true
    say "Attached: $sku ($label → $val)"
  fi
done

safe_curl GET "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
SCRIPT

# ---------- 6) SKRIV SCRIPT: add-by-id.sh ----------
cat > add-by-id.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"
: "${PARENT_SKU:=TEST-CFG}"; : "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"; : "${SOURCE_CODE:=default}"
: "${NEW_VAL_ID:?Need NEW_VAL_ID}"; : "${NEW_LABEL:?Need NEW_LABEL}"; : "${NEW_SKU:?Need NEW_SKU}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"
: "${ADMIN_USER:=}"; : "${ADMIN_PASS:=}"

refresh_token() {
  [ -z "${ADMIN_USER:-}" ] && return 0
  [ -z "${ADMIN_PASS:-}" ] && return 0
  local new
  new="$(curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
    | sed -e 's/^\"//' -e 's/\"$//')" || true
  if [ -n "$new" ] && [ "$new" != "${AUTH_ADMIN#Authorization: Bearer }" ]; then
    AUTH_ADMIN="Authorization: Bearer $new"
  fi
}
SAFE_CURL_PLACEHOLDER

name="TEST $NEW_LABEL"

body="$(jq -n --arg sku "$NEW_SKU" --arg name "$name" --argjson val "$NEW_VAL_ID" --argjson wid "$WEBSITE_ID" \
  '{product:{sku:$sku,name:$name,type_id:"simple",attribute_set_id:4,visibility:1,price:399,status:1,weight:1,
             extension_attributes:{website_ids:[$wid]},
             custom_attributes:[{attribute_code:"'"$ATTR_CODE"'",value:$val}]}}')"
safe_curl POST "$WRITE_BASE/products" "$body" >/dev/null || true

qty="${NEW_QTY:-5}"
stock="$(jq -n --arg sku "$NEW_SKU" --argjson q "$qty" \
  '{sourceItems:[{sku:$sku,source_code:"'"$SOURCE_CODE"'",quantity:$q,status:1}]}' )"
safe_curl POST "$WRITE_BASE/inventory/source-items" "$stock" >/dev/null || true

attr_id="$(safe_curl GET "$READ_BASE/products/attributes/$ATTR_CODE" | jq -r '.attribute_id')"
real_id="$(safe_curl GET "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes" \
  | jq -r --arg id "$attr_id" '.extension_attributes.configurable_product_options // [] | map(select(.attribute_id==$id)) | .[0].id // empty')"

if [ -n "${real_id:-}" ]; then
  have="$(safe_curl GET "$READ_BASE/products/$PARENT_SKU?fields=extension_attributes" \
    | jq -c --arg id "$attr_id" '.extension_attributes.configurable_product_options // [] | map(select(.attribute_id==$id)) | .[0].values // [] | map(.value_index) // []')"
  merged="$(jq -c --argjson a "$have" --argjson c "[$NEW_VAL_ID]" '($a + $c) | unique')"
  data="$(jq -n --arg id "$attr_id" --argjson vals "$merged" \
     '{option:{attribute_id:$id,label:"Config Color",position:0,is_use_default:true,values:($vals|map({value_index:.}))}}')"
  safe_curl PUT "$WRITE_BASE/configurable-products/$PARENT_SKU/options/$real_id" "$data" >/dev/null
fi

safe_curl POST "$WRITE_BASE/configurable-products/$PARENT_SKU/child" "{\"childSku\":\"$NEW_SKU\"}" >/dev/null || true

safe_curl GET "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
SCRIPT

# ---------- 7) PATCH inn safe_curl i begge skriptene ----------
for f in variant-sync.sh add-by-id.sh; do
  awk -v repl="$safe_curl_tpl" '{gsub("SAFE_CURL_PLACEHOLDER", repl);}1' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  chmod +x "$f"
done

# ---------- 8) Rask sanity test ----------
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/store/websites" >/dev/null && echo "✅ REST svarer."

echo
echo "✅ Ferdig! Kjør nå:  source ./.m2-env"
echo "Eksempler:"
echo "  ./variant-sync.sh"
echo "  NEW_VAL_ID=7 NEW_LABEL=Blue NEW_SKU=TEST-BLUE-EXTRA NEW_QTY=5 ./add-by-id.sh"
