#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")"/.. && pwd)"
. "$here/tools/_lib.sh"

load_magento_env
BASE="${BASE:-http://localhost:3000}"

MAG_REST="$(magento_base_rest)"
if [[ -z "${MAGENTO_URL:-${MAGENTO_BASE_URL:-}}" ]]; then
  echo "❌ MAGENTO_URL/MAGENTO_BASE_URL mangler i .env.local"; exit 1
fi

SKU="${1:-}"
if [[ -z "$SKU" ]]; then
  echo "Bruk: tools/ibu-fix-pack.sh <SKU>"; exit 1
fi

echo "🔎 BASE (app): $BASE"
echo "🔎 Magento REST: $MAG_REST"
echo "🔎 SKU: $SKU"

# 1) Opprett/oppdater IBU-attributtet via appens update-attributes (prøver flere felt)
try_codes=('ibu' 'cfg_ibu' 'akeneo_ibu')
ok=""
for code in "${try_codes[@]}"; do
  echo "🛠  Setter $code = '37' på $SKU via app-API…"
  res="$(curl -s -i -X PATCH "$BASE/api/products/update-attributes" \
    -H 'Content-Type: application/json' \
    -H 'x-magento-auth: admin' \
    -d "{\"sku\":\"$SKU\",\"attributes\":{\"$code\":\"37\"}}")"
  http="$(printf "%s" "$res" | awk 'NR==1{print $2}')"
  body="$(printf "%s" "$res" | sed -n '/^\r\?$/,$p' | tail -n +2)"
  echo "   → HTTP $http"
  if [[ "$http" == "200" ]]; then ok="$code"; break; fi
done

if [[ -z "$ok" ]]; then
  echo "⚠️  Ingen feltnavn akseptert via app-API. Fortsetter, men visning kan utebli."
else
  echo "✅ Persist OK via app-API med code=$ok"
fi

# 2) Verifiser fra GET /api/products/<SKU>
echo "🔎 Verifiserer at IBU dukker opp i produkt-data…"
curl -s "$BASE/api/products/$SKU" | jq '.custom_attributes[]? | select(.attribute_code=="ibu" or .attribute_code=="cfg_ibu" or .attribute_code=="akeneo_ibu") // empty'
echo "ℹ️  Hvis tomt, bruker Magento annet kodenavn enn forsøkt."
