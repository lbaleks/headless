#!/usr/bin/env bash
set -euo pipefail
FILE="${1:-skus.csv}"   # CSV: sku,ibu,ibu2,srm,hop_index,malt_index
while IFS=, read -r sku ibu ibu2 srm hop hopm; do
  [ -z "$sku" ] && continue
  attrs=()
  [ -n "${ibu:-}" ] && attrs+=("\"ibu\":\"$ibu\"")
  [ -n "${ibu2:-}" ] && attrs+=("\"ibu2\":\"$ibu2\"")
  [ -n "${srm:-}" ] && attrs+=("\"srm\":\"$srm\"")
  [ -n "${hop:-}" ] && attrs+=("\"hop_index\":\"$hop\"")
  [ -n "${hopm:-}" ] && attrs+=("\"malt_index\":\"$hopm\"")
  json="{\"sku\":\"$sku\",\"attributes\":{${attrs[*]//,/,\ }}}"
  curl -s -X PATCH 'http://localhost:3000/api/products/update-attributes' \
    -H 'Content-Type: application/json' -d "$json" >/dev/null
  echo "✓ $sku"
done < "$FILE"
