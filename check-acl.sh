#!/usr/bin/env bash
set -euo pipefail
: "${BASE:?}"; : "${AUTH_ADMIN:?}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"

msg=$(curl -sS -i -X PUT -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  --data '{"product":{"sku":"TEST","name":"TEST"}}' \
  "$WRITE_BASE/products/TEST" | tail -n1)

case "$msg" in
  *"Magento_Catalog::products"*)
    echo "❌ Missing ACL: Magento_Catalog::products (give Catalog → Products)"; exit 1;;
  *"sku"*)
    echo "✅ Write OK"; exit 0;;
  *)
    echo "ℹ️  Unexpected response: $msg"; exit 2;;
esac