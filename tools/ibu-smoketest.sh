#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

"$DIR/ibu-assert-env.sh" >/dev/null

# Reload exports here too
eval "$(
  awk -F= '/^MAGENTO_/ && $2 { gsub(/\r/,"",$2); gsub(/^["'"'"']|["'"'"']$/,"",$2); printf("export %s=\"%s\"\n",$1,$2) }' "$DIR/../.env.local"
)"

BASE="http://localhost:3000"
V1="${MAGENTO_URL%/}/V1"

# Admin JWT
ADMIN_JWT="$(curl -sS -X POST "$V1/integration/admin/token" \
  -H 'Content-Type: application/json' \
  --data '{"username":"'"${MAGENTO_ADMIN_USERNAME:-}"'","password":"'"${MAGENTO_ADMIN_PASSWORD:-}"'"}' | tr -d '"')"

if [[ -z "$ADMIN_JWT" || "$ADMIN_JWT" == null ]]; then
  echo "❌ Fikk ikke admin JWT. Sjekk brukernavn/pass i .env.local"; exit 1
fi

SKU="${1:-TEST-RED}"
VAL="${2:-37}"

echo "✍️  PATCH via app: $SKU.ibu=$VAL, ibu2=$VAL"
curl -s -X PATCH "$BASE/api/products/update-attributes" \
  -H 'Content-Type: application/json' \
  -d '{"sku":"'"$SKU"'","attributes":{"ibu":"'"$VAL"'","ibu2":"'"$VAL"'"}}' \
  | jq '.success' | grep -q true

echo "🧹 Reindex + flush"
"$DIR/ibu-reindex-and-flush.sh" >/dev/null || true

echo "🔎 GET single"
curl -s "$BASE/api/products/$SKU" | jq '{sku, ibu, _attrs:{ibu:._attrs.ibu, ibu2:._attrs.ibu2}}'

echo "🔎 GET merged"
curl -s "$BASE/api/products/merged?page=1&size=200" \
  | jq '.items[]? | select(.sku=="'"$SKU"'") | {sku, ibu, _attrs:{ibu:._attrs.ibu, ibu2:._attrs.ibu2}}'
