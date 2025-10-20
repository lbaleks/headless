#!/bin/sh
set -e

prompt() { printf "%s: " "$1" 1>&2; read -r "$2"; }

# 1) Hent BASE, user/pass
[ -n "$BASE" ] || prompt "BASE (f.eks. https://m2-dev.litebrygg.no)" BASE
[ -n "$ADMIN_USER" ] || prompt "ADMIN_USER" ADMIN_USER
if [ -z "$ADMIN_PASS" ]; then
  printf "ADMIN_PASS: " 1>&2
  stty -echo 2>/dev/null || true
  read -r ADMIN_PASS
  stty echo 2>/dev/null || true
  printf "\n" 1>&2
fi

: "${PARENT_SKU:=TEST-CFG}"
: "${ATTR_CODE:=cfg_color}"
: "${WEBSITE_ID:=1}"
: "${SOURCE_CODE:=default}"

# 2) Login → token
TOKEN_RAW=$(curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
  -H 'Content-Type: application/json' \
  --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")
AUTH_ADMIN="Authorization: Bearer $(printf '%s' "$TOKEN_RAW" | sed -e 's/^"//' -e 's/"$//')"

# 3) Sanity: REST OK?
curl -fsS -H "$AUTH_ADMIN" "$BASE/rest/V1/store/websites" >/dev/null

# 4) Skriv .m2-env for videre bruk
{
  printf 'export BASE=%s\n' "$BASE"
  printf 'export AUTH_ADMIN=%s\n' "$AUTH_ADMIN"
  printf 'export PARENT_SKU=%s\n' "$PARENT_SKU"
  printf 'export ATTR_CODE=%s\n' "$ATTR_CODE"
  printf 'export WEBSITE_ID=%s\n' "$WEBSITE_ID"
  printf 'export SOURCE_CODE=%s\n' "$SOURCE_CODE"
} > .m2-env

echo "✅ OK. Kjør:  source ./.m2-env"
echo "Tilgjengelige steg:"
echo "  NEW_LABEL=Purple NEW_SKU=TEST-PURPLE NEW_QTY=12 ./add-color.sh"
echo "  ./variant-sync.sh"
echo "  ./remove-color.sh TEST-PURPLE"

# 5) Valgfritt: ett auto-steg direkte (sett AUTO=add|sync|remove og evt NEW_LABEL/NEW_SKU/NEW_QTY/REMOVE_SKU)
case "$AUTO" in
  add)
    [ -n "$NEW_LABEL" ] && [ -n "$NEW_SKU" ] || { echo "AUTO=add krever NEW_LABEL og NEW_SKU"; exit 1; }
    [ -n "$NEW_QTY" ] || NEW_QTY=5
    . ./.m2-env
    NEW_LABEL="$NEW_LABEL" NEW_SKU="$NEW_SKU" NEW_QTY="$NEW_QTY" ./add-color.sh
    ;;
  sync)
    . ./.m2-env
    ./variant-sync.sh
    ;;
  remove)
    [ -n "$REMOVE_SKU" ] || { echo "AUTO=remove krever REMOVE_SKU"; exit 1; }
    . ./.m2-env
    ./remove-color.sh "$REMOVE_SKU"
    ;;
esac