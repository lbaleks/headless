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
