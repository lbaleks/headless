#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"

CURL_OPTS=${CURL_OPTS:---connect-timeout 5 --max-time 25 --retry 2 --retry-delay 1 --fail}
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"

refresh_token() {
  [ -n "${ADMIN_USER:-}" ] && [ -n "${ADMIN_PASS:-}" ] || return 1
  local t
  t=$(curl -sS --connect-timeout 5 --max-time 10 \
       -H 'Content-Type: application/json' \
       -X POST "$BASE/rest/V1/integration/admin/token" \
       --data "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
       | sed -e 's/^"//' -e 's/"$//') || return 1
  export AUTH_ADMIN="Authorization: Bearer $t"
}

safe_curl() {
  local method=$1; shift
  local url=$1; shift
  local out
  set +e
  out=$(curl -sS $CURL_OPTS -X "$method" -H "$AUTH_ADMIN" "$url" "$@" 2>&1)
  rc=$?
  set -e
  # Hvis 401: prøv å refreshe token én gang
  if [ $rc -ne 0 ] || grep -q '"message":"The consumer isn'\''t authorized' <<<"$out"; then
    if refresh_token; then
      out=$(curl -sS $CURL_OPTS -X "$method" -H "$AUTH_ADMIN" "$url" "$@" 2>&1)
      rc=$?
    fi
  fi
  if [ $rc -ne 0 ]; then
    echo "❌ HTTP $method $url" >&2
    printf '↳ body head: %s\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return $rc
  fi
  printf '%s' "$out"
}
