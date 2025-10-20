#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}
echo "→ Families:"; curl -s "$BASE/api/akeneo/families" | jq '.families[0].code'
echo "→ Channels:"; curl -s "$BASE/api/akeneo/channels" | jq '.channels[0].code,.locales[0].code'
echo "→ Completeness (beer/ecommerce/nb_NO)"
curl -s "$BASE/api/products/completeness?family=beer&channel=ecommerce&locale=nb_NO&page=1&size=1" | jq '.family,.channel,.locale, .items[0].completeness'
