#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
ENV_LOCAL="$ROOT/.env.local"

echo "→ Ensure canonical Magento env vars in .env.local"
# Pull values from existing .env/.env.local (MAGENTO_*, M2_*), prefer MAGENTO_*
pick(){ grep -E "^[[:space:]]*$1[[:space:]]*=" "$2" 2>/dev/null | tail -n1 | sed -E 's/.*=[[:space:]]*//; s/^["'\'' ]*//; s/["'\'' ]*$//'; }
BASE="$(pick MAGENTO_BASE_URL .env.local || true)"; [ -z "$BASE" ] && BASE="$(pick M2_BASE_URL .env || true)"; [ -z "$BASE" ] && BASE="$(pick NEXT_PUBLIC_GATEWAY_BASE .env.local || true)"
TOKEN="$(pick MAGENTO_ADMIN_TOKEN .env.local || true)"; [ -z "$TOKEN" ] && TOKEN="$(pick M2_ADMIN_TOKEN .env || true)"; [ -z "$TOKEN" ] && TOKEN="$(pick M2_TOKEN .env.local || true)"
MULT="$(pick PRICE_MULTIPLIER .env.local || true)"
BASIC="$(pick M2_BASIC .env.local || true)"

# Ensure /rest suffix
if [ -n "${BASE:-}" ]; then
  BASE="${BASE%/}"
  case "$BASE" in
    */rest) : ;;
    *) BASE="$BASE/rest" ;;
  esac
fi

# Rewrite .env.local canonically
{
  echo "# Generated/normalized by tools/install-debug-env.sh"
  [ -n "${BASE:-}" ]  && echo "MAGENTO_BASE_URL=$BASE"
  [ -n "${TOKEN:-}" ] && echo "MAGENTO_ADMIN_TOKEN=$TOKEN"
  [ -n "${BASE:-}" ]  && echo "NEXT_PUBLIC_GATEWAY_BASE=$BASE"
  [ -n "${MULT:-}" ]  && echo "PRICE_MULTIPLIER=$MULT"
  [ -n "${BASIC:-}" ] && echo "M2_BASIC=$BASIC"
} > "$ENV_LOCAL"

echo "→ Add JSON debug route /api/_debug/env"
mkdir -p app/api/_debug/env
cat > app/api/_debug/env/route.ts <<'TS'
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function GET() {
  const base =
    process.env.MAGENTO_BASE_URL ||
    process.env.M2_BASE_URL ||
    process.env.NEXT_PUBLIC_GATEWAY_BASE || '';
  const token =
    process.env.MAGENTO_ADMIN_TOKEN ||
    process.env.M2_ADMIN_TOKEN ||
    process.env.M2_TOKEN || '';

  return NextResponse.json({
    ok: Boolean(base && token),
    hasBase: !!base,
    hasToken: !!token,
    base,
    tokenPrefix: token ? token.slice(0, 8) + '…' : null,
  });
}
TS

echo "→ Clear Next cache"
rm -rf .next .next-cache 2>/dev/null || true

echo "✓ Done. Now run:  npm run dev"
echo "Then test:       curl -s http://localhost:3000/api/_debug/env | jq"
