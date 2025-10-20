#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:3000}"
start=$(date -Iseconds)
p=$(curl -s -X POST "$BASE/api/products/sync" | jq -r '.saved // 0')
c=$(curl -s -X POST "$BASE/api/customers/sync" | jq -r '.saved // 0')
o=$(curl -s -X POST "$BASE/api/orders/sync"   | jq -r '.saved // 0')
end=$(date -Iseconds)
curl -s -X POST "$BASE/api/jobs" -H 'content-type: application/json' \
  --data "{\"type\":\"sync-all\",\"started\":\"$start\",\"finished\":\"$end\",\"counts\":{\"products\":$p,\"customers\":$c,\"orders\":$o}}" | jq .
