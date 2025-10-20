#!/bin/bash
set -euo pipefail
echo "🔧 Stabiliserer Next dev + ID→SKU i produkt-oppdatering + ren build"

# 1) Minimal, stabil ESM-konfig for Next (fjerner custom webpack-cache i dev)
cat > next.config.mjs <<'MJS'
/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  experimental: { reactCompiler: true },
};
export default config;
MJS
echo "🛠  Skrev minimal next.config.mjs"

# (valgfritt) sørg for at gammel CJS-config ikke plukkes opp
[ -f next.config.js ] && mv -f next.config.js next.config.js.bak || true

# 2) Patch update-attributes: støtt numerisk id (entity_id) → slå opp SKU før PUT
awk 'BEGIN{p=1}
/^export async function PATCH/ {p=0}
{ if(p) print }' app/api/products/update-attributes/route.ts > app/api/products/update-attributes/route.tmp || true

cat > app/api/products/update-attributes/route.ts <<'TS'
// app/api/products/update-attributes/route.ts
import { NextResponse } from 'next/server'
import { revalidateTag } from 'next/cache'
import { getMagentoConfig, magentoUrl } from '../../_lib/env'

export const runtime = 'nodejs'

type UpdatePayload = { sku: string; attributes: Record<string, any> }
type MagentoProduct = {
  sku: string
  name?: string
  price?: number
  status?: number
  visibility?: number
  weight?: number
  attribute_set_id?: number
  type_id?: string
  custom_attributes?: Array<{ attribute_code: string; value: any }>
}

function isNumericId(s: string) { return /^[0-9]+$/.test(String(s||'')) }

function toCustomMap(arr?: Array<{attribute_code:string; value:any}>) {
  const m = new Map<string, any>()
  if (Array.isArray(arr)) for (const it of arr) m.set(it.attribute_code, it.value)
  return m
}
function fromCustomMap(m: Map<string, any>) {
  return Array.from(m.entries()).map(([attribute_code, value]) => ({ attribute_code, value }))
}
const TOP_LEVEL = new Set(['sku','name','price','status','visibility','weight','attribute_set_id','type_id'])

async function fetchProduct(baseUrl: string, token: string, sku: string): Promise<MagentoProduct | null> {
  const url = magentoUrl(baseUrl, 'products/' + encodeURIComponent(sku))
  const res = await fetch(url, { headers: { Authorization: 'Bearer ' + token } })
  if (res.status === 404) return null
  if (!res.ok) throw new Error(await res.text())
  return await res.json()
}
async function lookupSkuByEntityId(baseUrl: string, token: string, id: string): Promise<string | null> {
  const url = magentoUrl(
    baseUrl,
    'products?'
    + 'searchCriteria[filterGroups][0][filters][0][field]=entity_id&'
    + 'searchCriteria[filterGroups][0][filters][0][value]='+encodeURIComponent(id)+'&'
    + 'searchCriteria[filterGroups][0][filters][0][condition_type]=eq&'
    + 'searchCriteria[pageSize]=1'
  )
  const res = await fetch(url, { headers: { Authorization: 'Bearer ' + token } })
  if (!res.ok) return null
  const data = await res.json() as any
  const item = Array.isArray(data?.items) && data.items.length ? data.items[0] : null
  return item?.sku || null
}

function buildUpdatePayload(current: MagentoProduct | null, partial: Record<string, any>): MagentoProduct {
  const base: MagentoProduct = {
    sku: String(partial.sku || current?.sku || ''),
    attribute_set_id: current?.attribute_set_id,
    type_id: current?.type_id || 'simple',
    name: current?.name,
    price: current?.price,
    status: current?.status,
    visibility: current?.visibility,
    weight: current?.weight,
    custom_attributes: current?.custom_attributes || []
  }
  const top: Record<string, any> = {}
  const custom = new Map<string, any>(toCustomMap(base.custom_attributes))
  for (const [k, v] of Object.entries(partial)) {
    if (k === 'sku') continue
    if (TOP_LEVEL.has(k)) top[k] = v
    else custom.set(k, v)
  }
  const merged: MagentoProduct = { ...base, ...top, custom_attributes: fromCustomMap(custom) }
  const clean: any = {}
  for (const [k, v] of Object.entries(merged)) {
    if (v === undefined) continue
    if (k === 'custom_attributes' && Array.isArray(v) && v.length === 0) continue
    clean[k] = v
  }
  return clean as MagentoProduct
}

async function handleUpdate(req: Request) {
  try {
    const body = (await req.json()) as UpdatePayload
    if (!body || !body.sku || !body.attributes) {
      return NextResponse.json({ error: 'Missing "sku" or "attributes" in body' }, { status: 400 })
    }

    const { baseUrl, token } = await getMagentoConfig()

    // ID→SKU bridge for lagring også
    let sku = body.sku
    if (isNumericId(sku)) {
      const realSku = await lookupSkuByEntityId(baseUrl, token, sku)
      if (!realSku) return NextResponse.json({ error: 'No product for entity_id', id: sku }, { status: 404 })
      sku = realSku
    }

    const current = await fetchProduct(baseUrl, token, sku)
    const product = buildUpdatePayload(current, { sku, ...body.attributes })

    const url = magentoUrl(baseUrl, 'products/' + encodeURIComponent(sku))
    const res = await fetch(url, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
      body: JSON.stringify({ product })
    })
    if (!res.ok) {
      const text = await res.text()
      return NextResponse.json({ error: 'Magento update failed', detail: text, url, sent: product }, { status: res.status || 500 })
    }

    try { revalidateTag('products') } catch {}
    try { revalidateTag('products:merged') } catch {}
    try { revalidateTag('product:' + sku) } catch {}
    try { revalidateTag('completeness:' + sku) } catch {}

    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json({ error: 'Update attributes failed', detail: String(e?.message || e) }, { status: 500 })
  }
}

export async function PATCH(req: Request) { return handleUpdate(req) }
export async function POST(req: Request)  { return handleUpdate(req) }
TS

# 3) Ren build: slett all tidligere build-cache
rm -rf .next node_modules/.cache 2>/dev/null || true

echo "✅ Ferdig. Start på nytt: pnpm dev"
