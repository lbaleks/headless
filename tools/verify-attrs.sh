#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}
echo "→ Verify attributes persist"
jq -n '{sku:"TEST", attributes:{ibu: 62}}' \
| curl -s -X PATCH "$BASE/api/products/update-attributes" \
    -H 'content-type: application/json' --data-binary @- >/dev/null
test -f var/attributes/TEST.json
jq -e '.ibu == 62' var/attributes/TEST.json >/dev/null
echo "✓ OK"
