#!/usr/bin/env bash
set -e
echo "→ Installerer completeness (merged + sku + family-overlay)"

TARGET="app/api/products/completeness/route.ts"
mkdir -p "$(dirname "$TARGET")"

cat > "$TARGET" <<'TS'
// app/api/products/completeness/route.ts
import { NextResponse } from 'next/server'
import path from 'path'
import fs from 'fs'

type Product = {
  sku: string
  name?: string
  price?: number
  status?: number
  visibility?: number
  image?: string | null
  family?: string
  [k: string]: any
}

const DEFAULT_FAMILY = 'default'
const REQUIRED_BY_FAMILY: Record<string, string[]> = {
  default: ['sku', 'name', 'price', 'status', 'visibility'],
  beer: ['sku', 'name', 'price', 'status', 'visibility', 'image'],
}

function loadLocalFamilyMap(): Map<string, string> {
  const tryFiles = [
    path.join(process.cwd(), 'var', 'products.dev.json'),
    path.join(process.cwd(), 'var', 'products.local.json'),
  ]
  for (const f of tryFiles) {
    try {
      if (!fs.existsSync(f)) continue
      const raw = fs.readFileSync(f, 'utf8')
      const json = JSON.parse(raw)
      const arr: any[] = Array.isArray(json)
        ? json
        : Array.isArray(json?.items)
        ? json.items
        : []
      const m = new Map<string, string>()
      for (const it of arr) {
        if (it?.sku && it?.family) m.set(String(it.sku), String(it.family))
      }
      return m
    } catch {}
  }
  return new Map()
}

function famFor(p: Product) {
  return String(p?.family ?? (p as any)?.attributes?.family ?? DEFAULT_FAMILY)
}

function computeCompleteness(item: Product) {
  const required = REQUIRED_BY_FAMILY[item.family!] ?? REQUIRED_BY_FAMILY[DEFAULT_FAMILY]
  const missing = required.filter((k) => {
    const v = (item as any)[k]
    return v === undefined || v === null || v === '' || (typeof v === 'number' && Number.isNaN(v))
  })
  const score = Math.round(((required.length - missing.length) / required.length) * 100)
  return { score, missing, required }
}

export async function GET(req: Request) {
  try {
    const url = new URL(req.url)
    const page = url.searchParams.get('page') ?? '1'
    const size = url.searchParams.get('size') ?? '50'
    const q = url.searchParams.get('q') ?? ''
    const skuParam = url.searchParams.get('sku')

    const famBySku = loadLocalFamilyMap()

    let items: Product[] = []

    if (skuParam) {
      const r = await fetch(`${url.origin}/api/products/${encodeURIComponent(skuParam)}`, { cache: 'no-store' })
      if (r.ok) {
        const p: Product = await r.json()
        items = p ? [p] : []
      } else {
        return NextResponse.json({ ok: false, error: `Upstream /api/products/${skuParam} failed`, status: r.status }, { status: 502 })
      }
    } else {
      const mergedUrl = new URL(`${url.origin}/api/products/merged`)
      mergedUrl.searchParams.set('page', page)
      mergedUrl.searchParams.set('size', size)
      if (q) mergedUrl.searchParams.set('q', q)
      const r = await fetch(mergedUrl.toString(), { cache: 'no-store' })
      if (!r.ok) {
        return NextResponse.json({ ok: false, error: 'Upstream /api/products/merged failed', status: r.status }, { status: 502 })
      }
      const json = await r.json()
      items = Array.isArray(json?.items) ? json.items : []
    }

    const itemsWithFamily = items.map((it) => ({
      ...it,
      family: famBySku.get(String(it.sku)) ?? famFor(it),
    }))

    const mapped = itemsWithFamily.map((item) => ({
      sku: item.sku,
      name: item.name,
      family: item.family ?? DEFAULT_FAMILY,
      channel: 'ecommerce',
      locale: 'nb_NO',
      completeness: computeCompleteness(item),
    }))

    return NextResponse.json({
      ok: true,
      family: 'default',
      channel: 'ecommerce',
      locale: 'nb_NO',
      total: mapped.length,
      items: mapped,
    })
  } catch (err: any) {
    return NextResponse.json({ ok: false, error: String(err?.message ?? err) }, { status: 500 })
  }
}
TS

echo "✓ Skrev $TARGET"

echo "→ Starter dev (silent)"
npm run dev --silent >/dev/null 2>&1 & sleep 1

echo "→ Røyk-tester completeness"
BASE=${BASE:-http://localhost:3000}

echo "• Enkel SKU:"
curl -s "$BASE/api/products/completeness?sku=TEST" | jq '.items[0] | {sku, family, completeness}'

echo "• Bulk-sjekk:"
curl -s "$BASE/api/products/completeness?page=1&size=500" | jq '.items[] | select(.sku=="TEST") | {sku, family, completeness}'

echo "✓ Ferdig (completeness autoinstaller)"