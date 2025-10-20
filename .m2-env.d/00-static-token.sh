: "${BASE:?}"; : "${AUTH_ADMIN:?}"

# CURL_JSON METHOD URL [--data ...]
CURL_JSON() {
  local method="$1"; shift
  local url="$1"; shift
  local resp http
  resp=$(curl --fail --show-error --silent \
           -H "$AUTH_ADMIN" -H 'Content-Type: application/json' -H 'Expect:' \
           --write-out $'\nHTTP:%{http_code}\n' \
           -X "$method" "$url" "$@") || return 1
  http=$(printf '%s\n' "$resp" | tail -n1 | sed 's/HTTP://')
  printf '%s\n' "$resp" | sed '$d'    # body only
  [ "$http" -ge 200 ] && [ "$http" -lt 300 ]
}
