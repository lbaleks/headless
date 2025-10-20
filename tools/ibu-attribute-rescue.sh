#!/usr/bin/env bash
set -euo pipefail

: "${MAGENTO_ADMIN_USERNAME:?set MAGENTO_ADMIN_USERNAME in .env.local}"
: "${MAGENTO_ADMIN_PASSWORD:?set MAGENTO_ADMIN_PASSWORD in .env.local}"
: "${MAGENTO_URL:?set MAGENTO_URL in .env.local}"

V1="${MAGENTO_URL%/}/V1"
SKU="${1:-TEST-RED}"
IBUVAL="${2:-37}"
SET_ID="${3:-4}"       # attribute_set_id
GROUP_ID="${4:-20}"    # General group id

echo "🔐 Getting admin token…"
ADMIN_JWT="$(curl -sS -X POST "$V1/integration/admin/token" \
  -H 'Content-Type: application/json' \
  --data '{"username":"'"$MAGENTO_ADMIN_USERNAME"'","password":"'"$MAGENTO_ADMIN_PASSWORD"'"}' | tr -d '"')"

echo "🧪 Ensure attribute ibu2 exists (create if missing)…"
EXISTS="$(curl -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/attributes/ibu2" | jq -r '.attribute_code? // empty' || true)"
if [ "$EXISTS" != "ibu2" ]; then
  curl -sS -X POST "$V1/products/attributes" \
    -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
    --data '{
      "attribute": {
        "attribute_code": "ibu2",
        "default_frontend_label": "IBU",
        "frontend_input": "text",
        "backend_type": "varchar",
        "is_user_defined": true,
        "is_visible": true,
        "is_required": false,
        "is_comparable": false,
        "is_unique": false,
        "used_in_product_listing": 1,
        "is_visible_on_front": 1,
        "apply_to": [],
        "frontend_labels": [{ "store_id": 0, "label": "IBU" }]
      }
    }' | jq -r '{code:.attribute_code}'
else
  echo "   ibu2 already exists"
fi

echo "🔗 Assign ibu2 to set=$SET_ID group=$GROUP_ID (idempotent)…"
curl -sS -X POST "$V1/products/attribute-sets/attributes" \
  -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
  --data "{\"attributeSetId\":$SET_ID,\"attributeGroupId\":$GROUP_ID,\"attributeCode\":\"ibu2\",\"sortOrder\":10}" \
| jq -r '.message? // "OK or already assigned"'

echo "✍️  Write value to product ${SKU}…"
curl -sS -X PUT "$V1/products/$SKU" \
  -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
  --data "{
    \"product\": {
      \"sku\": \"${SKU}\",
      \"custom_attributes\": [{\"attribute_code\":\"ibu2\",\"value\":\"${IBUVAL}\"}]
    }
  }" | jq '{sku,updated_at}'

echo "🧹 Reindex/flush…"
# best-effort via your helper if present
if [ -x tools/ibu-reindex-and-flush.sh ]; then tools/ibu-reindex-and-flush.sh || true; fi

echo "🔎 Verify (raw Magento)…"
curl -sS -H "Authorization: Bearer $ADMIN_JWT" \
  "$V1/products/$SKU?storeId=0" | jq '.custom_attributes[]? | select(.attribute_code=="ibu2")'

echo "�� Verify (app routes)…"
curl -s "http://localhost:3000/api/products/$SKU" | jq '{sku, ibu, _attrs}'
curl -s "http://localhost:3000/api/products/merged?page=1&size=200" \
  | jq '.items[]? | select(.sku=="'"$SKU"'") | {sku, ibu, _attrs:{ibu2:._attrs.ibu2}}'
