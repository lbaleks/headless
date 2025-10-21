#!/usr/bin/env bash
set -euo pipefail

TARGET="app/api/debug/env/magento/route.ts"
BACKUP="${TARGET}.bak.$(date +%s)"
mkdir -p "$(dirname "$TARGET")"

echo "🔧 Backuper eksisterende route til $BACKUP"
[ -f "$TARGET" ] && cp "$TARGET" "$BACKUP" || true

cat > "$TARGET" <<'TS'
export const runtime = 'nodejs';
export const revalidate = 0;

import { NextResponse } from 'next/server';

function mask(v?: string | null) {
  if (!v) return '<empty>';
  if (v.length <= 5) return v[0] + '***';
  return v.slice(0,3) + '***' + v.slice(-2);
}

function stripBearer(v?: string | null) {
  if (!v) return v ?? undefined;
  return v.startsWith('Bearer ') ? v.slice(7) : v;
}

export async function GET() {
  const keys = [
    'MAGENTO_ADMIN_TOKEN',
    'MAGENTO_TOKEN',
    'MAGENTO_ACCESS_TOKEN',
    'M2_ADMIN_TOKEN',
    'M2_TOKEN',
  ] as const;

  // Bearer-varianter blir strippet og sjekket etterpå
  const bearerKeys = ['MAGENTO_ADMIN_BEARER','MAGENTO_BEARER','M2_BEARER'] as const;

  const env = process.env as Record<string,string|undefined>;
  const present: Record<string, boolean> = {};
  [...keys, ...bearerKeys].forEach(k => present[k] = Boolean(env[k]));

  let used: string | null = null;
  let token: string | undefined;

  for (const k of keys) {
    if (env[k]) { used = k; token = env[k]; break; }
  }
  if (!token) {
    for (const k of bearerKeys) {
      const t = stripBearer(env[k]);
      if (t) { used = k + ' (bearer)'; token = t; break; }
    }
  }

  const url = env.MAGENTO_URL || env.MAGENTO_BASE_URL || '';
  const MAGENTO_URL_preview = url.replace(/(https?:\/\/[^/]+).*/, '$1') + (url ? '/rest' : '');

  return NextResponse.json({
    ok: true,
    usedKey: used,
    presentKeys: present,
    MAGENTO_URL_preview,
    MAGENTO_TOKEN_masked: mask(token),
    note: 'Dette endepunktet er kun for debugging og viser maskert token + hvilken env-nøkkel som ble brukt.'
  });
}
TS

echo "✅ Skrev $TARGET"
echo "🧼 Renser .next og restarter…"
lsof -tiTCP:3000 -sTCP:LISTEN | xargs kill -9 2>/dev/null || true
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true
export PATH="$HOME/.volta/bin:$PATH"; hash -r
volta run pnpm run build
volta run pnpm start -p 3000 > /tmp/next.out 2>&1 & echo $! > /tmp/next.pid
sleep 1
echo "🔎 Tester /api/debug/env/magento"
curl -s http://localhost:3000/api/debug/env/magento | jq .
