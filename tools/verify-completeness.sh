#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}
echo "→ Verify completeness"
curl -s "$BASE/api/products/completeness?sku=TEST" \
  | jq '{item: (.items[0] // {} | {sku, family, completeness})}'
curl -s "$BASE/api/products/completeness?page=1&size=500" \
  | jq '[.items[] | select(.sku=="TEST") | {sku, family, score: .completeness.score}] | .[0]'
echo "✓ OK"
