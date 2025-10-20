#!/usr/bin/env bash
set -euo pipefail
base="${1:-http://localhost:3000}"

echo "→ Fjerner local overrides / dev-data"
rm -f var/products.dev.json var/customers.dev.json var/orders.dev.json || true

echo "→ Rydder Next cache"
rm -rf .next .next-cache 2>/dev/null || true

echo "→ Varm opp"
curl -s "$base/api/_debug/ping" | jq . || true
curl -s "$base/api/products?page=1&size=1"  | jq '.total' || true
curl -s "$base/api/customers?page=1&size=1" | jq '.total' || true
curl -s "$base/api/orders?page=1&size=1"    | jq '.total' || true

echo "✓ Done"