#!/usr/bin/env bash
set -euo pipefail

mkdir -p lib app/api/products/update-attributes app/api/products/[sku] app/api/products/merged

# --- lib/env.ts ---
cat > lib/env.ts <<'TS'
export function v1(baseUrl: string, path: string = ''): string {
  const b = (baseUrl || '').replace(/\/+$/, '')
  const p = path ? (path.startsWith('/') ? path : '/' + path) : ''
  return `${b}/V1${p}`
}

export function getMagentoConfig() {
  const baseUrl = process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || ''
  const adminUser = process.env.MAGENTO_ADMIN_USERNAME || null
  const adminPass = process.env.MAGENTO_ADMIN_PASSWORD || null
  const token = process.env.MAGENTO_TOKEN || ''
  return { baseUrl, adminUser, adminPass, token }
}

export async function getAdminToken(baseUrl: string, user: string|null, pass: string|null): Promise<string> {
  if (!baseUrl || !user || !pass) throw new Error('missing admin creds')
  const res = await fetch(v1(baseUrl, '/integration/admin/token'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: user, password: pass }),
    cache: 'no-store',
  })
  if (!res.ok) throw new Error(`admin token ${res.status}`)
  const raw = (await res.text()).trim()
  // Magento returns a JSON string like: "eyJ..."
  try {
    const j = JSON.parse(raw)
    if (typeof j === 'string') return j.trim()
  } catch {}
  return raw.replace(/^"|"$/g, '').trim()
}
TS

# --- app/api/products/update-attributes/route.ts ---
cat > app/api/products/update-attributes/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, getAdminToken, v1 } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type UpdatePayload = { sku: string; attributes: Record<string, string | number | null> }

export async function PATCH(req: Request) {
  try {
    const cfg = getMagentoConfig()
    if (!cfg.baseUrl) return NextResponse.json({ error: 'Missing Magento baseUrl' }, { status: 500 })

    const body = (await req.json().catch(() => ({}))) as Partial<UpdatePayload>
    const sku = (body?.sku ?? '').toString()
    if (!sku) return NextResponse.json({ error: 'Missing sku' }, { status: 400 })
    const entries = Object.entries(body?.attributes ?? {})
    const custom_attributes = entries.map(([attribute_code, value]) => ({ attribute_code, value }))

    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)

    const putRes = await fetch(v1(cfg.baseUrl, `/products/${encodeURIComponent(sku)}`), {
      method: 'PUT',
      headers: { 'Authorization': `Bearer ${jwt}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ product: { sku, custom_attributes } }),
      cache: 'no-store',
    })

    const txt = await putRes.text()
    if (!putRes.ok) {
      let payload: any = {}; try { payload = JSON.parse(txt) } catch {}
      return NextResponse.json({ error: `Magento PUT ${putRes.status}`, magento: payload || txt }, { status: 500 })
    }

    let magento: any = {}; try { magento = JSON.parse(txt) } catch {}
    return NextResponse.json({ success: true, magento })
  } catch (e: any) {
    return NextResponse.json({ error: String(e?.message || e) }, { status: 500 })
  }
}
TS

# --- app/api/products/[sku]/route.ts ---
cat > app/api/products/[sku]/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

export async function GET(_: Request, ctx: { params: Promise<{ sku: string }> }) {
  try {
    const { sku } = await ctx.params
    const cfg = getMagentoConfig()
    if (!cfg.baseUrl) return NextResponse.json({ error: 'Missing Magento baseUrl' }, { status: 500 })

    // Prefer admin JWT; fall back to fixed token if present
    const jwt = (cfg.adminUser && cfg.adminPass)
      ? await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
      : (cfg.token || '')
    const headers: Record<string, string> = jwt ? { Authorization: `Bearer ${jwt}` } : {}

    const url = v1(cfg.baseUrl, `/products/${encodeURIComponent(sku)}?storeId=0`)
    const res = await fetch(url, { headers, cache: 'no-store' })
    const txt = await res.text()
    if (!res.ok) {
      let payload: any = {}; try { payload = JSON.parse(txt) } catch {}
      return NextResponse.json({ error: `Magento GET ${res.status}`, magento: payload || txt }, { status: 500 })
    }

    let p: any = {}; try { p = JSON.parse(txt) } catch {}
    const ca = Array.isArray(p.custom_attributes) ? p.custom_attributes : []
    const attrs = Object.fromEntries(ca.filter(Boolean).map((x: any) => [x.attribute_code, x.value]))
    const ibu = attrs['ibu'] ?? null
    return NextResponse.json({ ...p, ibu, _attrs: attrs })
  } catch (e: any) {
    return NextResponse.json({ error: String(e?.message || e) }, { status: 500 })
  }
}
TS

# --- app/api/products/merged/route.ts ---
cat > app/api/products/merged/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

export async function GET(req: Request) {
  try {
    const url = new URL(req.url)
    const page = Math.max(1, parseInt(url.searchParams.get('page') || '1', 10))
    const size = Math.max(1, Math.min(200, parseInt(url.searchParams.get('size') || '20', 10)))
    const cfg = getMagentoConfig()
    if (!cfg.baseUrl) return NextResponse.json({ error: 'Missing Magento baseUrl' }, { status: 500 })

    const jwt = (cfg.adminUser && cfg.adminPass)
      ? await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
      : (cfg.token || '')
    const headers: Record<string, string> = jwt ? { Authorization: `Bearer ${jwt}` } : {}

    const qs = `searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}`
    const res = await fetch(v1(cfg.baseUrl, `/products?${qs}`), { headers, cache: 'no-store' })
    const txt = await res.text()
    if (!res.ok) {
      let payload: any = {}; try { payload = JSON.parse(txt) } catch {}
      return NextResponse.json({ error: `Magento GET ${res.status}`, magento: payload || txt }, { status: 500 })
    }

    let data: any = {}; try { data = JSON.parse(txt) } catch {}
    const items = Array.isArray(data?.items) ? data.items : []
    const lifted = items.map((p: any) => {
      const ca = Array.isArray(p.custom_attributes) ? p.custom_attributes : []
      const attrs = Object.fromEntries(ca.filter(Boolean).map((x: any) => [x.attribute_code, x.value]))
      const ibu = attrs['ibu'] ?? null
      return { ...p, ibu, _attrs: attrs }
    })
    return NextResponse.json({ items: lifted, page, size, total: data?.total_count ?? lifted.length })
  } catch (e: any) {
    return NextResponse.json({ error: String(e?.message || e) }, { status: 500 })
  }
}
TS

echo "✓ Wrote env and routes"
