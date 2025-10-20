#!/usr/bin/env bash
set -euo pipefail

echo "🛠  Litebrygg: installerer robust IBU-lagring + env-debug"

# --- Skriv PATCH-handler med verifisering og auto-admin-token ---
mkdir -p app/api/products/update-attributes
cat > app/api/products/update-attributes/route.ts <<'TS'
// app/api/products/update-attributes/route.ts
import { NextResponse } from 'next/server'
import { revalidateTag } from 'next/cache'

export const runtime = 'nodejs'
export const revalidate = 0
export const dynamic = 'force-dynamic'

type UpdatePayload = { sku: string; attributes: Record<string, any> }

function computeBaseV1(raw: string): string {
  let b = (raw || '').replace(/\/+$/, '')
  if (!b) return ''
  if (b.endsWith('/rest/V1')) return b
  if (b.endsWith('/rest')) return b + '/V1'
  return b + '/rest/V1'
}

async function getAdminToken(baseV1: string): Promise<string | null> {
  const username = process.env.MAGENTO_ADMIN_USERNAME || ''
  const password = process.env.MAGENTO_ADMIN_PASSWORD || ''
  if (!username || !password) return null
  const url = baseV1.replace(/\/V1$/, '') + '/V1/integration/admin/token'
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
    cache: 'no-store',
  })
  if (!res.ok) {
    const txt = await res.text().catch(() => '')
    console.error('Admin token fetch failed', res.status, txt)
    return null
  }
  const tokenRaw = await res.text()
  return tokenRaw.replace(/^"+|"+$/g, '')
}

async function magentoGetProduct(baseV1: string, token: string, sku: string) {
  const url = `${baseV1}/products/${encodeURIComponent(sku)}`
  const r = await fetch(url, { headers: { Authorization: `Bearer ${token}` }, cache: 'no-store' })
  const text = await r.text().catch(() => '')
  let json: any = null
  try { json = JSON.parse(text) } catch {}
  return { ok: r.ok, status: r.status, url, json, text }
}

function readIbuValue(p: any): string | undefined {
  const ca = Array.isArray(p?.custom_attributes) ? p.custom_attributes : []
  const map: Record<string, any> = {}
  for (const x of ca) if (x?.attribute_code) map[x.attribute_code] = x.value
  return map['ibu'] ?? map['cfg_ibu'] ?? map['akeneo_ibu']
}

async function tryPutOneCode(
  baseV1: string,
  token: string,
  sku: string,
  top: Record<string, any>,
  code: string,
  value: string | number,
) {
  const given = Array.isArray(top?.custom_attributes) ? [...top.custom_attributes] : []
  const cas = given.filter((x) => x?.attribute_code !== code)
  cas.push({ attribute_code: code, value: String(value) })
  const payload = { product: { ...top, custom_attributes: cas } }

  const url = `${baseV1}/products/${encodeURIComponent(sku)}`
  const res = await fetch(url, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(payload),
    cache: 'no-store',
  })
  const txt = await res.text().catch(() => '')
  if (!res.ok) {
    console.error('[Magento PUT failed]', { status: res.status, url, codeTried: code, body: txt })
    return { ok: false as const, status: res.status, body: txt }
  }
  const after = await magentoGetProduct(baseV1, token, sku)
  const got = readIbuValue(after.json)
  const matched = got != null && String(got) === String(value)
  return { ok: matched as boolean, status: res.status, verifiedValue: got }
}

export async function PATCH(req: Request) {
  try {
    const body = (await req.json()) as UpdatePayload
    if (!body?.sku || !body?.attributes) {
      return NextResponse.json({ error: 'Missing "sku" or "attributes" in body' }, { status: 400 })
    }

    const raw = process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || ''
    const baseV1 = computeBaseV1(raw)
    if (!baseV1) return NextResponse.json({ error: 'Missing MAGENTO_URL/MAGENTO_BASE_URL' }, { status: 500 })

    let token = process.env.MAGENTO_TOKEN || ''
    if (!token) {
      const admin = await getAdminToken(baseV1)
      if (admin) token = admin
    }
    if (!token) return NextResponse.json({ error: 'Missing MAGENTO_TOKEN and admin creds' }, { status: 500 })

    const desired = body.attributes.ibu ?? body.attributes.cfg_ibu ?? body.attributes.akeneo_ibu
    if (desired == null) {
      return NextResponse.json({ error: 'No IBU value provided (ibu/cfg_ibu/akeneo_ibu)' }, { status: 400 })
    }

    const candidates = ['ibu', 'cfg_ibu', 'akeneo_ibu']
    let used: string | null = null
    let lastDetail: any = null
    for (const code of candidates) {
      const r = await tryPutOneCode(baseV1, token, body.sku, body.attributes, code, desired)
      if (r.ok) { used = code; break }
      lastDetail = r
      if (r.status === 401 || r.status === 403) break
    }

    if (!used) {
      return NextResponse.json(
        { error: 'Magento update failed (no candidate code persisted)', detail: lastDetail },
        { status: 400 },
      )
    }

    try { revalidateTag('products') } catch {}
    return NextResponse.json({ success: true, codeUsed: used }, { headers: { 'Cache-Control': 'no-store' } })
  } catch (e: any) {
    console.error('Update attributes failed', e)
    return NextResponse.json({ error: e?.message || 'Unknown error' }, { status: 500 })
  }
}
TS

# --- Skriv et lite env-debug-endepunkt ---
mkdir -p app/api/debug/env/magento
cat > app/api/debug/env/magento/route.ts <<'TS'
// app/api/debug/env/magento/route.ts
import { NextResponse } from 'next/server'
export const runtime = 'nodejs'
export const revalidate = 0
export const dynamic = 'force-dynamic'
export async function GET() {
  const raw = (process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || '').replace(/\/+$/,'')
  const token = process.env.MAGENTO_TOKEN || ''
  const mask = (s:string) => s ? s.slice(0,3)+'…'+s.slice(-3) : '<empty>'
  return NextResponse.json({
    ok: true,
    MAGENTO_URL_preview: raw || '<empty>',
    MAGENTO_TOKEN_masked: mask(token),
    hasAdminCreds: !!process.env.MAGENTO_ADMIN_USERNAME && !!process.env.MAGENTO_ADMIN_PASSWORD,
  })
}
TS

echo "✅ Ferdig. Start appen på nytt: pnpm dev"
echo "🔎 Test env:  curl -s http://localhost:3000/api/debug/env/magento | jq"
echo "🧪 Test lagring: curl -i -X PATCH http://localhost:3000/api/products/update-attributes -H 'Content-Type: application/json' -d '{\"sku\":\"TEST-RED\",\"attributes\":{\"ibu\":\"37\"}}'"
