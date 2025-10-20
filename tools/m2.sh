#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pull() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$ROOT/.env.local" 2>/dev/null | tail -n1 | sed -E 's/^[^=]+=\s*//; s/^["'"'"']?//; s/["'"'"']?$//'; }

BASE="$(pull MAGENTO_BASE_URL || true)"
if [ -z "${BASE:-}" ]; then
  BASE="$(grep -E '^(MAGENTO_BASE_URL|M2_BASE_URL|NEXT_PUBLIC_GATEWAY_BASE)=' "$ROOT/.env.local" 2>/dev/null | head -n1 | sed -E 's/^[^=]+=\s*//; s/^["'"'"']?//; s/["'"'"']?$//')"
fi

TOKEN="$(grep -E '^(MAGENTO_ADMIN_TOKEN|M2_ADMIN_TOKEN|M2_TOKEN)=' "$ROOT/.env.local" 2>/dev/null | tail -n1 | sed -E 's/^[^=]+=\s*//; s/^["'"'"']?//; s/["'"'"']?$//')"

BASE="${BASE%/}"
[[ "$BASE" != */rest ]] && BASE="$BASE/rest"

[ $# -lt 1 ] && { echo "Usage: tools/m2.sh 'V1/products?searchCriteria[pageSize]=1'"; exit 1; }

curl --globoff -sS -H "Authorization: Bearer $TOKEN" "$BASE/$1"
