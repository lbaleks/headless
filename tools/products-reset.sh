#!/usr/bin/env bash
set -euo pipefail
echo "→ Fjerner var/products.dev.json"
rm -f var/products.dev.json || true
echo "→ Pinger produkt for å bygge opp på nytt"
curl -s "http://localhost:3000/api/products/TEST" | jq '.sku,.name,.source' || true
echo "✓ Done"