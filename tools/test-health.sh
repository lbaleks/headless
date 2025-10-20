#!/bin/bash
set -euo pipefail

SKU="${1:-11}"
BASE="${BASE_URL:-http://localhost:3000}"

echo "🩺 Tester API mot ${BASE} med SKU=${SKU}"

status() {
  local code="$1"; shift
  if [[ "$code" -ge 200 && "$code" -lt 300 ]]; then
    echo "   ✅ $*"
  else
    echo "   ❌ $*"
  fi
}

# 1) GET /api/products/[sku]
code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}/api/products/${SKU}")
status "$code" "GET /api/products/${SKU} → HTTP $code"

# 2) PATCH /api/products/update-attributes
payload='{"sku":"'"${SKU}"'","attributes":{"name":"HealthCheck '"$(date +%H:%M:%S)"'"}}'
resp=$(curl -s -o /tmp/resp.json -w "%{http_code}" -X PATCH "${BASE}/api/products/update-attributes" \
  -H "Content-Type: application/json" \
  -d "${payload}")
status "$resp" "PATCH /api/products/update-attributes → HTTP $resp"
if [[ "$resp" -ge 400 ]]; then
  echo "   ↪︎ Feildetaljer:"
  cat /tmp/resp.json | sed 's/^/      /'
fi

# 3) Re-test GET etter update for å se om 404 forsvinner
code2=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}/api/products/${SKU}")
status "$code2" "GET (etter PATCH) /api/products/${SKU} → HTTP $code2"

echo
echo "ℹ️  Tips:"
echo " - Hvis #1 = 404: SKU finnes trolig ikke i Magento. Test med en SKU fra /api/products/merged."
echo " - Hvis #2 = 401/403: sjekk MAGENTO_TOKEN i .env.local."
echo " - Hvis #2 = 400/500 med detail: se 'url' og 'detail' i responsen – det er direkte fra Magento."