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
