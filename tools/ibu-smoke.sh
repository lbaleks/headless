#!/usr/bin/env bash
set -euo pipefail
BASE="http://localhost:3000"
SKU="${1:-TEST-RED}"
VAL="${2:-42}"

echo "✍️  PATCH $SKU.ibu=$VAL, ibu2=$VAL"
curl -s -X PATCH "$BASE/api/products/update-attributes" \
  -H 'Content-Type: application/json' \
  --data "{\"sku\":\"$SKU\",\"attributes\":{\"ibu\":\"$VAL\",\"ibu2\":\"$VAL\"}}" >/dev/null

echo "🔎 SINGLE"
curl -s "$BASE/api/products/$SKU" \
 | jq '{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2}}'

echo "🔎 MERGED"
curl -s "$BASE/api/products/merged?page=1&size=50" \
 | jq '.items[]?|select(.sku=="'"$SKU"'")|{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2}}'