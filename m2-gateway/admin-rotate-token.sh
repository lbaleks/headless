#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-https://m2-dev.litebrygg.no}"
USER="${USER_NAME:-aleksander}"
PASS="${USER_PASS:-Riise1986!}"

RAW=$(curl -sS -X POST "$BASE/rest/V1/integration/admin/token" \
  -H 'Content-Type: application/json' \
  --data '{"username":"'"$USER"'","password":"'"$PASS"'"}')

# strip anførselstegn og whitespace
JWT=$(echo -n "$RAW" | tr -d '" \n\r\t')

if [[ "$JWT" != eyJ* ]]; then
  echo "Klarte ikke hente JWT: $RAW" >&2
  exit 1
fi

awk -v jwt="$JWT" 'BEGIN{OFS="="}
  $1=="MAGENTO_TOKEN"{print "MAGENTO_TOKEN","Bearer " jwt; next}
  {print}
' .env > .env.tmp && mv .env.tmp .env

pkill -f "node server.js" 2>/dev/null || true
node server.js >/dev/null 2>&1 & disown
echo "✅ Oppdatert MAGENTO_TOKEN (admin JWT) og restartet gateway."
