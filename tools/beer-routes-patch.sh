#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

write_single() {
cat > "$ROOT/app/api/products/[sku]/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type CA = { attribute_code: string; value: any }
type M2Product = { sku?: string|null; custom_attributes?: CA[]|null }

const ALIASES: Record<string,string[]> = {
  ibu: ['ibu','ibu2'],
  srm: ['srm','ebc'],
  hop_index: ['hop_index','hopint'],
  malt_index: ['malt_index','grain_index'],
}

function pickFirst(attrs: Record<string,any>, list: string[]) {
  for (const k of list) if (attrs[k] != null) return attrs[k]
  return null
}

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

  const ibu  = pickFirst(attrs, ALIASES.ibu)
  const srm  = pickFirst(attrs, ALIASES.srm)
  const hop  = pickFirst(attrs, ALIASES.hop_index)
  const malt = pickFirst(attrs, ALIASES.malt_index)

  return NextResponse.json({ ...(data||{}), ibu, srm, hop_index: hop, malt_index: malt, _attrs: attrs })
}
TS
}

write_merged() {
cat > "$ROOT/app/api/products/merged/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type CA = { attribute_code: string; value: any }
type M2Product = { sku?: string|null; custom_attributes?: CA[]|null }

const ALIASES: Record<string,string[]> = {
  ibu: ['ibu','ibu2'],
  srm: ['srm','ebc'],
  hop_index: ['hop_index','hopint'],
  malt_index: ['malt_index','grain_index'],
}

function pickFirst(attrs: Record<string,any>, list: string[]) {
  for (const k of list) if (attrs[k] != null) return attrs[k]
  return null
}

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
    const ibu  = pickFirst(attrs, ALIASES.ibu)
    const srm  = pickFirst(attrs, ALIASES.srm)
    const hop  = pickFirst(attrs, ALIASES.hop_index)
    const malt = pickFirst(attrs, ALIASES.malt_index)
    return { ...(p||{}), ibu, srm, hop_index: hop, malt_index: malt, _attrs: attrs }
  })

  return NextResponse.json({ items: lifted, page, size, total: data?.total_count ?? lifted.length })
}
TS
}

write_single
write_merged
echo " Patchet /api/products/[sku] og /merged (lfter ibu/srm/hop_index/malt_index)"
