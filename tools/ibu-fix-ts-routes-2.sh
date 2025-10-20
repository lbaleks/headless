#!/usr/bin/env bash
set -euo pipefail

root="$(pwd)"
sku_rt="$root/app/api/products/[sku]/route.ts"
merged_rt="$root/app/api/products/merged/route.ts"
mkdir -p "$(dirname "$sku_rt")" "$(dirname "$merged_rt")"

# Small local helper we inline in both files:
# mkV1('https://m2/rest') => 'https://m2/rest/V1'
# mkV1('https://m2')      => 'https://m2/rest/V1'
read -r -d '' COMMON_HELPER <<'TS'
function mkV1(baseUrl: string) {
  const trimmed = baseUrl.replace(/\/+$/,'')
  const withRest = trimmed.endsWith('/rest') ? trimmed : `${trimmed}/rest`
  return `${withRest}/V1`
}
function safeJson(t: string) {
  try { return JSON.parse(t) } catch { return t }
}
TS

# ---------- [sku]/route.ts ----------
cat > "$sku_rt" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, getAdminToken } from '@/lib/env'

export const runtime = 'nodejs'
export const revalidate = 0

function mkV1(baseUrl: string) {
  const trimmed = baseUrl.replace(/\/+$/,'')
  const withRest = trimmed.endsWith('/rest') ? trimmed : `${trimmed}/rest`
  return `${withRest}/V1`
}
function safeJson(t: string) {
  try { return JSON.parse(t) } catch { return t }
}

export async function GET(_req: Request, ctx: { params: Promise<{ sku: string }> }) {
  try {
    const { sku } = await ctx.params
    const cfg = getMagentoConfig()
    const baseUrl = (cfg && typeof cfg.baseUrl === 'string' ? cfg.baseUrl : '') as string
    if (!baseUrl) {
      return NextResponse.json({ error: 'Missing Magento baseUrl' }, { status: 500 })
    }

    let token = ''
    try { token = await getAdminToken() } catch { /* ignore */ }
    if (!token && cfg?.token) token = cfg.token
    if (!token) {
      return NextResponse.json({ error: 'Missing Magento token (admin or static)' }, { status: 500 })
    }

    const base = mkV1(baseUrl)
    const url = `${base}/products/${encodeURIComponent(sku)}?storeId=0&fields=attribute_set_id,sku,custom_attributes[attribute_code,value]`

    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } })
    if (!res.ok) {
      const text = await res.text().catch(() => '')
      return NextResponse.json({ error: `Magento ${res.status}`, body: safeJson(text) }, { status: res.status })
    }
    const data = await res.json()
    return NextResponse.json(data)
  } catch (err: any) {
    return NextResponse.json({ error: String(err?.message || err) }, { status: 500 })
  }
}
TS

# ---------- merged/route.ts ----------
cat > "$merged_rt" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, getAdminToken } from '@/lib/env'

export const runtime = 'nodejs'
export const revalidate = 0

function mkV1(baseUrl: string) {
  const trimmed = baseUrl.replace(/\/+$/,'')
  const withRest = trimmed.endsWith('/rest') ? trimmed : `${trimmed}/rest`
  return `${withRest}/V1`
}
function safeJson(t: string) {
  try { return JSON.parse(t) } catch { return t }
}

export async function GET(req: Request) {
  try {
    const u = new URL(req.url)
    const page = Math.max(1, Number(u.searchParams.get('page') || 1))
    const size = Math.max(1, Math.min(200, Number(u.searchParams.get('size') || 50)))

    const cfg = getMagentoConfig()
    const baseUrl = (cfg && typeof cfg.baseUrl === 'string' ? cfg.baseUrl : '') as string
    if (!baseUrl) {
      return NextResponse.json({ error: 'Missing Magento baseUrl' }, { status: 500 })
    }

    let token = ''
    try { token = await getAdminToken() } catch { /* ignore */ }
    if (!token && cfg?.token) token = cfg.token
    if (!token) {
      return NextResponse.json({ error: 'Missing Magento token (admin or static)' }, { status: 500 })
    }

    const base = mkV1(baseUrl)
    const query =
      `searchCriteria[currentPage]=${page}` +
      `&searchCriteria[pageSize]=${size}` +
      `&storeId=0` +
      `&fields=items[sku,attribute_set_id,custom_attributes[attribute_code,value]],total_count`
    const url = `${base}/products?${query}`

    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } })
    if (!res.ok) {
      const text = await res.text().catch(() => '')
      return NextResponse.json({ error: `Magento ${res.status}`, body: safeJson(text) }, { status: res.status })
    }
    const data = await res.json() as any

    const items = Array.isArray(data?.items) ? data.items : []
    const lifted = items.map((p: any) => {
      const ca = Array.isArray(p?.custom_attributes) ? p.custom_attributes : []
      const ibu = ca.find((x: any) => x && x.attribute_code === 'ibu')?.value ?? null
      const _attrs = Object.fromEntries(
        ca.filter((x: any) => x && typeof x.attribute_code === 'string')
          .map((x: any) => [x.attribute_code, x.value])
      )
      return { ...p, ibu, _attrs }
    })
    const total = Number.isFinite(data?.total_count) ? data.total_count : lifted.length

    return NextResponse.json({ items: lifted, page, size, total })
  } catch (err: any) {
    return NextResponse.json({ error: String(err?.message || err) }, { status: 500 })
  }
}
TS

echo "✓ Rewrote $sku_rt"
echo "✓ Rewrote $merged_rt"
