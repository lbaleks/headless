# tools/verify-single-route.sh
#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}

# Sjekk at single /api/products/:sku leverer JSON + familie
jq -e . >/dev/null < <(curl -fsS "$BASE/api/products/TEST")
jq -e '.sku=="TEST" and .family=="beer"' >/dev/null < <(curl -fsS "$BASE/api/products/TEST")

# Sjekk completeness for single
jq -e '.items[0].completeness.score==100' >/dev/null < <(curl -fsS "$BASE/api/products/completeness?sku=TEST")

echo "✓ single-route OK, completeness OK"