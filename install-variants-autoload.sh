#!/usr/bin/env bash
set -euo pipefail

# --- INPUTS ---
if [ -z "${BASE:-}" ]; then read -rp "BASE (e.g. https://m2-dev.litebrygg.no): " BASE; fi
BASE="${BASE%/}"
if [ -z "${ADMIN_USER:-}" ]; then read -rp "ADMIN_USER: " ADMIN_USER; fi
if [ -z "${ADMIN_PASS:-}" ]; then stty -echo 2>/dev/null||true; read -rp "ADMIN_PASS: " ADMIN_PASS; echo; stty echo 2>/dev/null||true; fi

b64url_decode(){ tr '_-' '/+' | base64 -D 2>/dev/null || base64 -d 2>/dev/null; }
now(){ date -u +%s; }
refresh_token(){ curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
 -H 'Content-Type: application/json' \
 --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
 | sed -e 's/^"//' -e 's/"$//' ; }
is_token_valid(){
  local t="${1:-}"; IFS='.' read -r _ p _ <<<"$t"||true
  [ -n "${p:-}" ] || return 1
  local exp; exp="$(printf '%s' "$p" | b64url_decode 2>/dev/null | jq -r '.exp // empty' 2>/dev/null || true)"
  [ -n "$exp" ] && [ "$exp" -gt $(( $(date -u +%s)+60 )) ]
}

ADMIN_TOKEN="${ADMIN_TOKEN:-}"
if ! is_token_valid "$ADMIN_TOKEN"; then ADMIN_TOKEN="$(refresh_token)"; fi
AUTH_HEADER="Authorization: Bearer $ADMIN_TOKEN"

curl -sS -H "$AUTH_HEADER" "$BASE/rest/V1/store/websites" >/dev/null || { echo "❌ REST ikke OK."; exit 1; }

cat > .m2-env <<ENV
export BASE='$BASE'
export AUTH_ADMIN='Authorization: Bearer $ADMIN_TOKEN'
export PARENT_SKU='TEST-CFG'
export ATTR_CODE='cfg_color'
export WEBSITE_ID='1'
export SOURCE_CODE='default'
export READ_BASE="\$BASE/rest/all/V1"
export WRITE_BASE="\$BASE/rest/V1"
ENV

echo "✅ Ferdig! Kjør:  source ./.m2-env"
