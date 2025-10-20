#!/bin/bash
set -euo pipefail
set +H  # disable history expansion so '!' in passwords isn't mangled

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
WRITE_ENV="${1:-}"   # 'write' to save into .env.local

if [ -z "$BASE_RAW" ] || [ -z "$USER" ] || [ -z "$PASS" ]; then
  echo "❌ Need MAGENTO_URL/MAGENTO_BASE_URL + MAGENTO_ADMIN_USERNAME + MAGENTO_ADMIN_PASSWORD"; exit 1
fi

BASE_RAW="${BASE_RAW%/}"; [[ "$BASE_RAW" == *"/rest" ]] || BASE_RAW="$BASE_RAW/rest"
URL="$BASE_RAW/V1/integration/admin/token"

echo "🔐 Fetching admin token from $URL for '$USER' ..."
resp="$(curl -s -w $'\n%{http_code}' -X POST "$URL" -H 'Content-Type: application/json' --data-binary @- <<'JSON'
{"username":"__USER__","password":"__PASS__"}
JSON
)"
# Substitute after to keep the here-doc static (no history expansion)
resp="${resp/__USER__/$USER}"
resp="${resp/__PASS__/$PASS}"

http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
if [ "$http" != "200" ]; then
  echo "❌ Admin-token failed (HTTP $http)"; echo "$body"; exit 1
fi

token="$(echo "$body" | sed -E 's/^"|"$//g')"
echo "✅ Admin token OK"

if [ "$WRITE_ENV" = "write" ]; then
  [ -f .env.local ] || touch .env.local
  tmp="$(mktemp)"
  grep -Ev '^[[:space:]]*MAGENTO_TOKEN=|^[[:space:]]*MAGENTO_PREFER_ADMIN_TOKEN=' .env.local > "$tmp" || true
  {
    echo "MAGENTO_TOKEN=$token"
    echo "MAGENTO_PREFER_ADMIN_TOKEN=1"
  } >> "$tmp"
  mv "$tmp" .env.local
  echo "📝 Wrote MAGENTO_TOKEN + MAGENTO_PREFER_ADMIN_TOKEN=1 to .env.local"
fi

# stdout token for piping
echo "$token"
