import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'

export const runtime = 'nodejs'
export const revalidate = 0

type PatchBody = {
  sku?: string
  attributes?: Record<string, any>
}

export async function PATCH(req: Request) {
  try {
    const body = (await req.json().catch(() => ({}))) as PatchBody
    const sku = (body?.sku || '').trim()
    if (!sku) {
      return NextResponse.json({ error: 'Missing sku' }, { status: 400 })
    }
    const attributes = body?.attributes || {}
    const custom_attributes = Object.entries(attributes)
      .filter(([k, v]) => k && v !== undefined)
      .map(([attribute_code, value]) => ({ attribute_code, value }))

    const cfg = getMagentoConfig()
    // Admin JWT every time (more reliable than integration token in your setup)
    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)

    const url = `${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}`
    const payload = {
      product: { sku, custom_attributes },
      saveOptions: true,
    }

    const putRes = await fetch(url, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${jwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
      cache: 'no-store',
    })

    const text = await putRes.text()
    let magento: any = {}
    try { magento = JSON.parse(text) } catch { magento = { raw: text } }

    if (!putRes.ok) {
      return NextResponse.json({ error: `Magento PUT ${putRes.status}`, magento }, { status: 500 })
    }

    return NextResponse.json({ success: true, magento })
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Unexpected error' }, { status: 500 })
  }
}
