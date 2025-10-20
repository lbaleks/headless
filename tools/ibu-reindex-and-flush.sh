#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Viktig: **source** – så variablene faktisk finnes i dette skriptet
. "$DIR/load-magento-env.sh"

: "${MAGENTO_URL:?set MAGENTO_URL i .env.local}"
: "${MAGENTO_ADMIN_USERNAME:?set MAGENTO_ADMIN_USERNAME i .env.local}"
: "${MAGENTO_ADMIN_PASSWORD:?set MAGENTO_ADMIN_PASSWORD i .env.local}"

V1="${MAGENTO_URL%/}/V1"

JWT="$(curl -sS -X POST "$V1/integration/admin/token" \
  -H 'Content-Type: application/json' \
  --data '{"username":"'"$MAGENTO_ADMIN_USERNAME"'","password":"'"$MAGENTO_ADMIN_PASSWORD"'"}' \
  | tr -d '"')"

# Reindex (ufarlig å kjøre flere ganger)
curl -sS -X POST "$V1/indexer/reindex" \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  --data '["catalog_product_attribute","catalog_product_price","inventory"]' >/dev/null || true

# Flush caches
curl -sS -X POST "$V1/cache/flush" \
  -H "Authorization: Bearer $JWT" >/dev/null || true

echo "✓ Reindexed + flushed caches"
