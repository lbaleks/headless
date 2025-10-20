#!/usr/bin/env bash
set -euo pipefail
export BASE="https://m2-dev.litebrygg.no"
export ADMIN_USER="aleksander"
export ADMIN_PASS='<<PASS_HER>>'   # <-- bytt

BASE="${BASE%/}"; BASE="${BASE%%#*}"; BASE="${BASE%%[[:space:]]*}"
ADMIN_TOKEN=$(curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
  -H 'Content-Type: application/json' \
  --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
  | sed -e 's/^"//' -e 's/"$//') || { echo "Token-feil"; exit 1; }

mkdir -p .m2-env.d
cat > .m2-env <<ENV
export BASE='$BASE'
export AUTH_ADMIN='Authorization: Bearer $ADMIN_TOKEN'
export PARENT_SKU='TEST-CFG'
export ATTR_CODE='cfg_color'
export WEBSITE_ID='1'
export SOURCE_CODE='default'
export READ_BASE="\$BASE/rest/all/V1"
export WRITE_BASE="\$BASE/rest/V1"
[ -f "./.m2-env.d/10-autorefresh.sh" ] && . "./.m2-env.d/10-autorefresh.sh"
ENV

cat > .m2-env.d/10-autorefresh.sh <<'R'
: "${BASE:?}"; : "${READ_BASE:="$BASE/rest/all/V1"}"; : "${WRITE_BASE:="$BASE/rest/V1"}"
REFRESH_TOKEN(){ [ -z "${ADMIN_USER:-}" ]&&{ echo "ADMIN_USER mangler"; return 1;}
 [ -z "${ADMIN_PASS:-}" ]&&{ echo "ADMIN_PASS mangler"; return 1;}
 local t; t=$(curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
   -H 'Content-Type: application/json' \
   --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
   | sed -e 's/^"//' -e 's/"$//') || return 1
 export AUTH_ADMIN="Authorization: Bearer $t"
}
CURL_JSON(){ local m="$1"; shift; local u="$1"; shift; local resp http
 resp=$(curl --fail --show-error --silent -H "$AUTH_ADMIN" -H 'Content-Type: application/json' -H 'Expect:' \
   --write-out $'\nHTTP:%{http_code}\n' -X "$m" "$u" "$@")
 http=$(printf '%s\n' "$resp" | tail -n1 | sed 's/HTTP://')
 if [ "$http" = "401" ]; then REFRESH_TOKEN || { echo "❌ Refresh feilet"; return 1; }
   resp=$(curl --fail --show-error --silent -H "$AUTH_ADMIN" -H 'Content-Type: application/json' -H 'Expect:' \
     --write-out $'\nHTTP:%{http_code}\n' -X "$m" "$u" "$@")
   http=$(printf '%s\n' "$resp" | tail -n1 | sed 's/HTTP://')
 fi
 printf '%s\n' "$resp" | sed '$d'; [ "$http" -ge 200 ] && [ "$http" -lt 300 ]
}
R

# selftest
. ./.m2-env
. ./.m2-env.d/10-autorefresh.sh
curl -sS -H "$AUTH_ADMIN" "$BASE/rest/V1/store/websites" >/dev/null && echo "REST OK"
name=$(curl -sS -H "$AUTH_ADMIN" "$WRITE_BASE/products/TEST" | jq -r '.name')
CURL_JSON PUT "$WRITE_BASE/products/TEST" --data "{\"product\":{\"sku\":\"TEST\",\"name\":\"$name\"}}" >/dev/null && echo "WRITE OK"
echo "Done. Kjør:  source ./.m2-env"
