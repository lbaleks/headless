import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type AttrMap = Record<string,string|number|null|undefined>

export async function PATCH(req: Request) {
  try {
    const { sku, attributes } = await req.json() as { sku?: string, attributes?: AttrMap }
    if (!sku || !attributes || typeof attributes !== 'object') {
      return NextResponse.json({ error: 'Bad request: need { sku, attributes }' }, { status: 400 })
    }

    const cfg = getMagentoConfig()
    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)

    // Convert to Magento custom_attributes[]
    const custom_attributes = Object.entries(attributes)
      .filter(([_,v]) => v !== undefined)
      .map(([attribute_code, value]) => ({ attribute_code, value: String(value ?? '') }))

    const res = await fetch(`${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}`, {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${jwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ product: { sku, custom_attributes }, saveOptions: true }),
      cache: 'no-store',
    })

    const text = await res.text()
    let json: any = null
    try { json = text ? JSON.parse(text) : null } catch { /* keep raw text */ }

    if (!res.ok) {
      return NextResponse.json({ error: `Magento PUT ${res.status}`, magento: json ?? text }, { status: 500 })
    }
    return NextResponse.json({ success: true, magento: json ?? { ok: true } })
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Unhandled' }, { status: 500 })
  }
}
