#!/bin/bash
set -euo pipefail
echo "🔧 Slår av webpack-cache i dev + gjør /api/products fresh og med flatten"

# 1) Next config (ESM): slå av webpack cache i dev (stabilt)
cat > next.config.mjs <<'MJS'
/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  experimental: { reactCompiler: true },
  webpack: (cfg, { dev }) => {
    if (dev) cfg.cache = false; // slå AV persistent cache i dev
    return cfg;
  },
};
export default config;
MJS
echo "🛠  Oppdatert next.config.mjs (dev: cache=false)"

# 2) /api/products → always fresh + flatten custom_attributes + paginering
mkdir -p app/api/products
cat > app/api/products/route.ts <<'TS'
// app/api/products/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '../_lib/env'

export const revalidate = 0
export const dynamic = 'force-dynamic'
export const runtime = 'nodejs'

function toInt(v: any, def: number) {
  const n = Number(v)
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : def
}

function flattenCustomAttributes(item: any) {
  const src = Array.isArray(item?.custom_attributes) ? item.custom_attributes : []
  const map: Record<string, any> = {}
  for (const ca of src) {
    if (!ca || !ca.attribute_code) continue
    map[ca.attribute_code] = ca.value
  }
  // Løft typiske felter som UI kan lese direkte (utvid listen ved behov)
  const liftKeys = [
    'ibu','cfg_ibu','akeneo_ibu',
    'tax_class_id','url_key','options_container','msrp_display_actual_price_type',
    'category_ids','required_options','has_options','cfg_color'
  ]
  for (const k of liftKeys) if (map[k] !== undefined && item[k] === undefined) item[k] = map[k]
  // Ta med hele attr-kartet også (nyttig i UI)
  item._attrs = map
  return item
}

export async function GET(req: Request) {
  try {
    const { baseUrl, token } = await getMagentoConfig()
    const urlObj = new URL(req.url)
    const page = toInt(urlObj.searchParams.get('page'), 1)
    const size = toInt(urlObj.searchParams.get('size'), 200)

    const url = magentoUrl(
      baseUrl,
      `products?searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}`
    )

    const res = await fetch(url, {
      headers: { Authorization: 'Bearer ' + token },
      cache: 'no-store',
      next: { tags: ['products','products:merged'] }, // slik at begge blir revalidert
    })

    if (!res.ok) {
      return NextResponse.json({ ok:false, error: await res.text(), url }, { status: res.status })
    }

    const data = await res.json()
    if (Array.isArray(data?.items)) {
      data.items = data.items.map(flattenCustomAttributes)
      return NextResponse.json(
        { ok:true, page, size, total_count: data.total_count ?? data.items.length, items: data.items },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    // fallback (hvis APIet svarer i annen form)
    return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } })
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: String(e?.message || e) }, { status: 500 })
  }
}
TS
echo "🛠  Opprettet/oppdatert /api/products (fresh + flatten + pagination)"

# 3) Rydd bygg-cacher for ren start
rm -rf .next node_modules/.cache 2>/dev/null || true
echo "🧹 Ryddet .next og node_modules/.cache"

echo "✅ Ferdig. Start dev på nytt: pnpm dev"
