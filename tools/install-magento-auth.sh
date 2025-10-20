#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "→ Oppretter mapper…"
mkdir -p "$ROOT/src/lib" "$ROOT/app/api/_debug/env" "$ROOT/app/api/_debug/ping" "$ROOT/tools"

echo "→ Skriver src/lib/magento.ts (auto login + refresh)…"
cat > "$ROOT/src/lib/magento.ts" <<'TS'
export const __isServer = typeof window === 'undefined'

const RAW_BASE =
  process.env.MAGENTO_BASE_URL ||
  process.env.M2_BASE_URL ||
  process.env.NEXT_PUBLIC_GATEWAY_BASE

function normalizeBase(v?: string | null) {
  if (!v) return undefined
  const base = v.replace(/\/+$/, '')
  return base.endsWith('/rest') ? base : base + '/rest'
}

export const BASE = normalizeBase(RAW_BASE)
let cachedToken: string | null =
  process.env.MAGENTO_ADMIN_TOKEN ||
  process.env.M2_ADMIN_TOKEN ||
  process.env.M2_TOKEN ||
  null

const USER =
  process.env.MAGENTO_ADMIN_USERNAME || process.env.M2_ADMIN_USERNAME
const PASS =
  process.env.MAGENTO_ADMIN_PASSWORD || process.env.M2_ADMIN_PASSWORD

async function ensureToken(): Promise<string> {
  if (!__isServer) throw new Error('Magento client used on client')
  if (!BASE) throw new Error('Missing MAGENTO_BASE_URL / M2_BASE_URL / NEXT_PUBLIC_GATEWAY_BASE')

  if (cachedToken) return cachedToken

  if (!USER || !PASS) {
    throw new Error('Missing admin token and MAGENTO_ADMIN_USERNAME/MAGENTO_ADMIN_PASSWORD')
  }

  const res = await fetch(`${BASE}/V1/integration/admin/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: USER, password: PASS }),
    cache: 'no-store',
  })
  if (!res.ok) {
    const sample = await res.text().catch(() => '')
    throw new Error(`Magento auth failed ${res.status} ${sample}`)
  }
  const token = await res.json()
  if (typeof token !== 'string') throw new Error('Unexpected token response')
  cachedToken = token
  // gjør tilgjengelig for andre moduler i samme prosess
  process.env.MAGENTO_ADMIN_TOKEN = token
  return token
}

async function request<T>(verb: string, path: string, body?: any): Promise<T> {
  if (!BASE) throw new Error('Missing MAGENTO_BASE_URL / M2_BASE_URL / NEXT_PUBLIC_GATEWAY_BASE')
  const token = await ensureToken()
  const url = `${BASE}/${path.replace(/^\//, '')}`

  const res = await fetch(url, {
    method: verb,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: body == null ? undefined : JSON.stringify(body),
    cache: 'no-store',
  })

  // Ved utløpt token: prøv én gang til
  if (res.status === 401 || res.status === 403) {
    cachedToken = null
    if (USER && PASS) {
      await ensureToken()
      const retry = await fetch(url, {
        method: verb,
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${cachedToken}`,
        },
        body: body == null ? undefined : JSON.stringify(body),
        cache: 'no-store',
      })
      if (!retry.ok) {
        const sample = await retry.text().catch(() => '')
        throw new Error(`Magento ${verb} ${url} failed after refresh: ${retry.status} ${sample}`)
      }
      return retry.json() as Promise<T>
    }
  }

  if (!res.ok) {
    const sample = await res.text().catch(() => '')
    throw new Error(`Magento ${verb} ${url} failed: ${res.status} ${sample}`)
  }
  return res.json() as Promise<T>
}

export const m2 = {
  BASE,
  get: <T>(path: string) => request<T>('GET', path),
  post: <T>(path: string, body?: any) => request<T>('POST', path, body),
  put:  <T>(path: string, body?: any) => request<T>('PUT', path, body),
  patch:<T>(path: string, body?: any) => request<T>('PATCH', path, body),
  delete:<T>(path: string) => request<T>('DELETE', path),
}
TS

echo "→ Sikrer tools/m2.sh (deaktiver curl-globs, støtt [] i query)…"
cat > "$ROOT/tools/m2.sh" <<'B2'
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
B2
chmod +x "$ROOT/tools/m2.sh"

echo "→ Liten debug-endpoint (env)…"
cat > "$ROOT/app/api/_debug/env/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { BASE } from '@/src/lib/magento'

export async function GET() {
  return NextResponse.json({
    ok: true,
    hasBase: !!BASE,
    hasToken: !!process.env.MAGENTO_ADMIN_TOKEN || !!process.env.M2_ADMIN_TOKEN || !!process.env.M2_TOKEN,
    base: BASE,
    tokenPrefix: (process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || process.env.M2_TOKEN || '').slice(0, 6) + '…',
  })
}
TS

echo "→ Liten debug-endpoint (ping)…"
cat > "$ROOT/app/api/_debug/ping/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { m2 } from '@/src/lib/magento'

export async function GET() {
  const out:any = { base: m2.BASE, tokenPrefix: (process.env.MAGENTO_ADMIN_TOKEN||'').slice(0,6) + '…', checks: [] }
  // Best-effort: ordrer, produkter, kunder
  const endpoints = [
    { name: 'orders',    url: 'V1/orders?searchCriteria[pageSize]=1' },
    { name: 'products',  url: 'V1/products?searchCriteria[pageSize]=1' },
    { name: 'customers', url: 'V1/customers/search?searchCriteria[pageSize]=1' },
  ]
  for (const ep of endpoints) {
    try {
      const data = await m2.get<any>(ep.url)
      out.checks.push({ ok: true, status: 200, url: `${m2.BASE}/${ep.url}`, sample: Array.isArray(data?.items) ? {items:data.items.slice(0,1), total_count:data.total_count} : data })
    } catch (e:any) {
      out.checks.push({ ok: false, status: e?.message?.match(/\s(\d{3})\s/)?Number(RegExp.$1):0, url: `${m2.BASE}/${ep.url}`, sample: String(e?.message||e) })
    }
  }
  return NextResponse.json(out)
}
TS

echo "→ Tips om .env.local"
if ! grep -q '^MAGENTO_BASE_URL=' "$ROOT/.env.local" 2>/dev/null; then
  echo "MAGENTO_BASE_URL=<https://din-magento/rest>" >> "$ROOT/.env.local"
fi
if ! grep -q '^MAGENTO_ADMIN_USERNAME=' "$ROOT/.env.local" 2>/dev/null; then
  echo "MAGENTO_ADMIN_USERNAME=" >> "$ROOT/.env.local"
fi
if ! grep -q '^MAGENTO_ADMIN_PASSWORD=' "$ROOT/.env.local" 2>/dev/null; then
  echo "MAGENTO_ADMIN_PASSWORD=" >> "$ROOT/.env.local"
fi

echo "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true
echo "✓ Ferdig. Start dev-server på nytt (npm run dev / yarn dev / pnpm dev)."
