#!/bin/bash
set -euo pipefail
set +H  # slå av bash history expansion (for '!' i passord)

need() {
  local key="$1" val="${!key-}"; if [ -n "${val:-}" ]; then echo "$val"; return 0; fi
  local f; for f in .env.local .env; do
    if [ -f "$f" ]; then
      val="$(grep -E "^[[:space:]]*${key}=" "$f" | tail -n1 | sed -E "s/^[[:space:]]*${key}=//" | sed -E "s/^['\"]?(.*)['\"]?$/\1/")"
      if [ -n "$val" ]; then echo "$val"; return 0; fi
    fi
  done; echo ""
}

BASE_RAW="$(need MAGENTO_BASE_URL)"; [ -n "$BASE_RAW" ] || BASE_RAW="$(need MAGENTO_URL)"
USER="$(need MAGENTO_ADMIN_USERNAME)"
PASS="$(need MAGENTO_ADMIN_PASSWORD)"
WRITE_ENV="${1:-}"   # 'write' for å lagre i .env.local

if [ -z "$BASE_RAW" ] || [ -z "$USER" ] || [ -z "$PASS" ]; then
  echo "❌ Trenger MAGENTO_URL/MAGENTO_BASE_URL + MAGENTO_ADMIN_USERNAME + MAGENTO_ADMIN_PASSWORD"; exit 1
fi

BASE_RAW="${BASE_RAW%/}"; [[ "$BASE_RAW" == *"/rest" ]] || BASE_RAW="$BASE_RAW/rest"
URL="$BASE_RAW/V1/integration/admin/token"

# Lag JSON trygt med Node (korrekt escaping)
BODY="$(node -e 'const u=process.env.U, p=process.env.P; console.log(JSON.stringify({username:u,password:p}))' U="$USER" P="$PASS")"

echo "🔐 Henter admin-token fra $URL for '$USER' ..."
resp="$(curl -s -w $'\n%{http_code}' -X POST "$URL" -H 'Content-Type: application/json' --data "$BODY")"
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
if [ "$http" != "200" ]; then
  echo "❌ Admin-token feilet (HTTP $http)"; echo "$body"; exit 1
fi

token="$(echo "$body" | sed -E 's/^"|"$//g')"
echo "✅ Admin-token OK"

if [ "$WRITE_ENV" = "write" ]; then
  [ -f .env.local ] || touch .env.local
  tmp="$(mktemp)"
  grep -Ev '^[[:space:]]*MAGENTO_TOKEN=|^[[:space:]]*MAGENTO_PREFER_ADMIN_TOKEN=' .env.local > "$tmp" || true
  {
    echo "MAGENTO_TOKEN=$token"
    echo "MAGENTO_PREFER_ADMIN_TOKEN=1"
  } >> "$tmp"
  mv "$tmp" .env.local
  echo "📝 Skrev MAGENTO_TOKEN + MAGENTO_PREFER_ADMIN_TOKEN=1 til .env.local"
fi

# print til stdout (for piping)
echo "$token"
