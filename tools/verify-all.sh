#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}

echo "→ Health"
curl -fsS "$BASE/api/debug/health" | jq -e '.ok==true' >/dev/null && echo "  ✓ OK"

echo "→ Jobs"
jid=$(curl -fsS -X POST "$BASE/api/jobs/run-sync" | jq -r '.id')
echo "  ✓ run-sync $jid"
curl -fsS "$BASE/api/jobs/latest" | jq -e --arg jid "$jid" '.item.id==$jid' >/dev/null && echo "  ✓ latest==$jid"

echo "→ Akeneo"
curl -fsS "$BASE/api/akeneo/families"  >/dev/null && echo "  ✓ families"
curl -fsS "$BASE/api/akeneo/channels"  >/dev/null && echo "  ✓ channels"
curl -fsS "$BASE/api/akeneo/attributes" >/dev/null && echo "  ✓ attributes"

echo "→ Completeness (single)"
curl -fsS "$BASE/api/products/completeness?sku=TEST" \
 | jq -e '.items[0].family=="beer" and .items[0].completeness.score==100' >/dev/null \
 && echo "  ✓ TEST=beer score=100"

echo "→ Completeness (bulk + scope/locale)"
curl -fsS "$BASE/api/products/completeness?page=1&size=5&channel=ecommerce&locale=nb_NO" \
 | jq -e '.channel=="ecommerce" and .locale=="nb_NO"' >/dev/null \
 && echo "  ✓ scope/locale"

echo "→ CSV"
curl -fsS "$BASE/api/products/export" | head -n1 | grep -q 'sku,name,price' && echo "  ✓ export"
echo "ok"