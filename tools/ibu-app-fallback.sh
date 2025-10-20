#!/usr/bin/env bash
set -euo pipefail

# 1) patch /api/products/[sku]
cat > app/api/products/[sku]/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type M2Product = { sku?: string; custom_attributes?: Array<{attribute_code:string,value:any}>|null }

export async function GET(_: Request, ctx: { params: { sku: string } }) {
  const { sku } = ctx.params
  const cfg = getMagentoConfig()
  const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
  const url = `${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
  if (!res.ok) {
    const err = await res.text().catch(()=>res.statusText)
    return NextResponse.json({ error: `Magento GET ${res.status}`, detail: err }, { status: 500 })
  }
  const data: M2Product = await res.json().catch(()=>({}))
  const ca = Array.isArray(data?.custom_attributes) ? data!.custom_attributes! : []
  const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))
  const ibu = attrs['ibu'] ?? null
  return NextResponse.json({ ...(data||{}), ibu, _attrs: attrs })
}
TS

# 2) patch /api/products/merged
cat > app/api/products/merged/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type M2Product = { sku?: string; custom_attributes?: Array<{attribute_code:string,value:any}>|null }

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = Number(searchParams.get('page')||'1')||1
  const size = Number(searchParams.get('size')||'50')||50
  const cfg = getMagentoConfig()
  const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)

  const url = `${v1(cfg.baseUrl)}/products?searchCriteria[current_page]=${page}&searchCriteria[page_size]=${size}&storeId=0`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
  if (!res.ok) {
    const err = await res.text().catch(()=>res.statusText)
    return NextResponse.json({ error: `Magento GET ${res.status}`, detail: err }, { status: 500 })
  }

  const data = await res.json().catch(()=>({}))
  const items: M2Product[] = Array.isArray(data?.items) ? data.items : []

  const lifted = items.map(p => {
    const ca = Array.isArray(p?.custom_attributes) ? p!.custom_attributes! : []
    const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))
    const ibu = attrs['ibu'] ?? null
    return { ...(p||{}), ibu, _attrs: attrs }
  })

  return NextResponse.json({ items: lifted, page, size, total: data?.total_count ?? lifted.length })
}
TS

echo "✓ Patched routes with IBU fallback."
