#!/bin/bash
set -euo pipefail

# Les env
need() {
  local key="$1" val="${!key-}"; if [ -n "${val:-}" ]; then echo "$val"; return 0; fi
  local f; for f in .env.local .env; do
    if [ -f "$f" ]; then
      val="$(grep -E "^[[:space:]]*${key}=" "$f" | tail -n1 | sed -E "s/^[[:space:]]*${key}=//" | sed -E "s/^['\"]?(.*)['\"]?$/\1/")"
      if [ -n "$val" ]; then echo "$val"; return 0; fi
    fi
  done; echo ""
}

BASE="$(need MAGENTO_URL)"; [ -n "$BASE" ] || BASE="$(need MAGENTO_BASE_URL)"
USER="$(need MAGENTO_ADMIN_USERNAME)"
PASS="$(need MAGENTO_ADMIN_PASSWORD)"
WRITE_ENV="${1:-}"   # bruk "write" for å skrive tilbake til .env.local

if [ -z "$BASE" ] || [ -z "$USER" ] || [ -z "$PASS" ]; then
  echo "❌ Mangler MAGENTO_URL/MAGENTO_BASE_URL eller admin brukernavn/passord i .env.local/.env"; exit 1
fi

BASE="${BASE%/}"
[[ "$BASE" == *"/rest" ]] || BASE="$BASE/rest"

echo "🔐 Henter admin-token fra $BASE/V1/integration/admin/token for bruker '$USER' ..."
resp="$(curl -s -w $'\n%{http_code}' -X POST "$BASE/V1/integration/admin/token" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"$PASS\"}")"
http="${resp##*$'\n'}"; body="${resp%$'\n'*}"

if [ "$http" != "200" ]; then
  echo "❌ Admin-token feilet (HTTP $http)"; echo "$body"; exit 1
fi

token="$(echo "$body" | sed -E 's/^"|"$//g')"
echo "✅ Admin-token OK"

if [ "$WRITE_ENV" = "write" ]; then
  # skriv/erstatér MAGENTO_TOKEN og preferanse i .env.local
  if [ ! -f .env.local ]; then touch .env.local; fi
  tmp="$(mktemp)"
  # fjern eksisterende linjer
  grep -Ev '^[[:space:]]*MAGENTO_TOKEN=|^[[:space:]]*MAGENTO_PREFER_ADMIN_TOKEN=' .env.local > "$tmp" || true
  {
    echo "MAGENTO_TOKEN=$token"
    echo "MAGENTO_PREFER_ADMIN_TOKEN=1"
  } >> "$tmp"
  mv "$tmp" .env.local
  echo "📝 Skrev MAGENTO_TOKEN og MAGENTO_PREFER_ADMIN_TOKEN=1 til .env.local"
fi

# skriv token til stdout for piping
echo "$token"
