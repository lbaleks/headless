#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:3000}"
echo "→ Sync products…"
curl -s -X POST "$BASE/api/products/sync" | jq .
echo "→ Sync customers…"
curl -s -X POST "$BASE/api/customers/sync" | jq .
echo "→ Sync orders…"
curl -s -X POST "$BASE/api/orders/sync" | jq .
echo "→ Totals:"
printf "  products: %s\n" "$(curl -s "$BASE/api/products?page=1&size=1"  | jq -r '.total // 0')"
printf "  customers: %s\n" "$(curl -s "$BASE/api/customers?page=1&size=1" | jq -r '.total // 0')"
printf "  orders:   %s\n" "$(curl -s "$BASE/api/orders?page=1&size=1"    | jq -r '.total // 0')"
