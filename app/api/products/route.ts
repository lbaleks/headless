export const runtime = 'nodejs';
// app/api/products/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '../_lib/env'

export const revalidate = 0
export const dynamic = 'force-dynamic'

function toInt(v: any, def: number) {
  const n = Number(v)
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : def
}

function flattenCustomAttributes(item: any) {
  const arr = Array.isArray(item && item.custom_attributes) ? item.custom_attributes : []
  const map: Record<string, any> = {}
  for (let i = 0; i < arr.length; i++) {
    const ca = arr[i]
    if (!ca || !ca.attribute_code) continue
    map[ca.attribute_code] = ca.value
  }

  // Løft vanlige felter + sett item.ibu med fallback
  const liftKeys = [
    'ibu', 'cfg_ibu', 'akeneo_ibu', 'IBU', 'ibu_value',
    'tax_class_id', 'url_key', 'options_container', 'msrp_display_actual_price_type',
    'category_ids', 'required_options', 'has_options', 'cfg_color'
  ]
  for (let i = 0; i < liftKeys.length; i++) {
    const k = liftKeys[i]
    if (map[k] !== undefined && (item as any)[k] === undefined) (item as any)[k] = map[k]
  }
  const ibuCand = (map as any)['ibu'] !== undefined ? (map as any)['ibu']
    : (map as any)['cfg_ibu'] !== undefined ? (map as any)['cfg_ibu']
    : (map as any)['akeneo_ibu'] !== undefined ? (map as any)['akeneo_ibu']
    : (map as any)['IBU'] !== undefined ? (map as any)['IBU']
    : (map as any)['ibu_value']
  if (ibuCand !== undefined) (item as any).ibu = ibuCand

  ;(item as any)._attrs = map
  return item
}

export async function GET(req: Request) {
  try {
    const { baseUrl, token } = await getMagentoConfig()
    const urlObj = new URL(req.url)
    const page = toInt(urlObj.searchParams.get('page'), 1)
    const size = toInt(urlObj.searchParams.get('size'), 200)

    const qs =
      'products?' +
      'searchCriteria[currentPage]=' + String(page) +
      '&searchCriteria[pageSize]=' + String(size)

    const url = magentoUrl(baseUrl, qs)

    const res = await fetch(url, {
      headers: { Authorization: 'Bearer ' + token },
      cache: 'no-store',
      next: { tags: ['products', 'products:merged'] },
    })

    if (!res.ok) {
      const text = await res.text()
      return NextResponse.json({ ok: false, error: text, url }, { status: res.status })
    }

    const data: any = await res.json()

    if (data && Array.isArray(data.items)) {
      const items = data.items.map(flattenCustomAttributes)
      const total = typeof data.total_count === 'number' ? data.total_count : items.length
      return NextResponse.json(
        { ok: true, page, size, total_count: total, items },
        { headers: { 'Cache-Control': 'no-store' } }
      )
    }

    // Fallback hvis API svarer i annen form
    return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } })
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: String(e?.message || e) }, { status: 500 })
  }
}
