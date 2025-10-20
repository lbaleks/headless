#!/bin/bash
set -euo pipefail
echo "🔧 Litebrygg: Safe-merge for Magento product update + clean .next"

# 1) Overwrite update-attributes til å hente eksisterende produkt og merge
cat > app/api/products/update-attributes/route.ts <<'TS'
// app/api/products/update-attributes/route.ts
import { NextResponse } from 'next/server'
import { revalidateTag } from 'next/cache'
import { getMagentoConfig, magentoUrl } from '../../_lib/env'

export const runtime = 'nodejs'

type UpdatePayload = {
  sku: string
  attributes: Record<string, any>
}

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

function buildUpdatePayload(current: MagentoProduct | null, partial: Record<string, any>): MagentoProduct {
  // Start med et minimalt “lovlig” objekt
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

  // Del opp feltene: toppnivå vs custom_attributes
  const top: Record<string, any> = {}
  const custom = new Map<string, any>(toCustomMap(base.custom_attributes))

  for (const [k, v] of Object.entries(partial)) {
    if (k === 'sku') continue
    if (TOP_LEVEL.has(k)) top[k] = v
    else {
      // map “category_ids”, “tax_class_id”, osv. som custom attributes
      custom.set(k, v)
    }
  }

  const merged: MagentoProduct = {
    ...base,
    ...top,
    custom_attributes: fromCustomMap(custom)
  }

  // Rydd vekk tomme/undefined fields (Magento liker ikke “undefined”)
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

    // 1) Hent eksisterende produkt
    const current = await fetchProduct(baseUrl, token, body.sku)

    // 2) Bygg trygg payload
    const product = buildUpdatePayload(current, { sku: body.sku, ...body.attributes })

    // 3) PUT
    const url = magentoUrl(baseUrl, 'products/' + encodeURIComponent(body.sku))
    const res = await fetch(url, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + token
      },
      body: JSON.stringify({ product })
    })

    if (!res.ok) {
      const text = await res.text()
      return NextResponse.json({ error: 'Magento update failed', detail: text, url, sent: product }, { status: res.status || 500 })
    }

    // 4) Revalidate
    try { revalidateTag('products') } catch {}
    try { revalidateTag('product:' + body.sku) } catch {}
    try { revalidateTag('completeness:' + body.sku) } catch {}

    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json({ error: 'Update attributes failed', detail: String(e?.message || e) }, { status: 500 })
  }
}

export async function PATCH(req: Request) { return handleUpdate(req) }
export async function POST(req: Request)  { return handleUpdate(req) }
TS

# 2) Clean .next så Next bygger alt på nytt (hindrer ENOENT-peking på gamle artefakter)
if [ -d ".next" ]; then
  echo "🧹 Cleaning .next/"
  rm -rf .next
fi

echo "✅ Safe-merge oppdatert og build-cache renset."
echo "➡  Start på nytt: pnpm dev"
