#!/usr/bin/env bash
set -euo pipefail
V1="${MAGENTO_URL%/}/V1"
ADMIN_JWT="$(curl -sS -X POST "$V1/integration/admin/token" -H 'Content-Type: application/json' \
  --data '{"username":"'"$MAGENTO_ADMIN_USERNAME"'","password":"'"$MAGENTO_ADMIN_PASSWORD"'"}' | tr -d '"')"
RESP="$(curl -sS -X PUT "$V1/products/attributes/ibu" -H "Authorization: Bearer $ADMIN_JWT" \
  -H 'Content-Type: application/json' --data '{"attribute":{"attribute_code":"ibu"}}')"
if echo "$RESP" | jq -e '.parameters.resources=="Magento_Catalog::attributes_attributes"' >/dev/null 2>&1; then
  echo "❌ Missing ACL: Catalog → Attributes → Product (Magento_Catalog::attributes_attributes). Fix role permissions for this admin."
  exit 1
fi
echo "✅ Attribute ACL looks OK (response from Magento):"
echo "$RESP" | jq .
