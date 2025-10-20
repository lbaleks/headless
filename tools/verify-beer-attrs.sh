#!/usr/bin/env bash
set -euo pipefail
sku="${1:-TEST-RED}"
base="http://localhost:3000"

echo "🔎 $sku → single"
curl -s "$base/api/products/$sku" \
 | jq '{sku, ibu, srm, hop_index, malt_index, _attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2}}'

echo "🔎 $sku → merged"
curl -s "$base/api/products/merged?page=1&size=200" \
 | jq ".items[]?|select(.sku==\"$sku\")|{sku, ibu, srm, hop_index, malt_index, _attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2}}"
