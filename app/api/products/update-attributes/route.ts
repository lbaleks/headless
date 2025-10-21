export const runtime = 'nodejs';
import { NextResponse } from 'next/server'

const MAGENTO_BASE_URL = process.env.MAGENTO_BASE_URL || process.env.MAGENTO_URL || ''
const MAGENTO_ADMIN_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || ''

function toMagentoAttributes(attrs: Record<string,string>) {
  return Object.entries(attrs).map(([attribute_code, value]) => ({ attribute_code, value }))
}

export async function PATCH(req: Request) {
  try {
    const { sku, attributes } = await req.json() as { sku: string, attributes: Record<string,string> }
    if (!sku || !attributes) {
      return NextResponse.json({ error: 'Bad request' }, { status: 400 })
    }
    const custom_attributes = toMagentoAttributes(attributes)
    const url = `${MAGENTO_BASE_URL.replace(/\/$/, '')}/V1/products/${encodeURIComponent(sku)}`
    const res = await fetch(url, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        ...(MAGENTO_ADMIN_TOKEN ? { 'Authorization': `Bearer ${MAGENTO_ADMIN_TOKEN}` } : {})
      },
      body: JSON.stringify({ product: { sku, custom_attributes }, saveOptions: true }),
      cache: 'no-store'
    })

    if (!res.ok) {
      // prøv json -> tekst -> statusText
      let detail: any
      try { detail = await res.json() } 
      catch { try { detail = await res.text() } catch { detail = res.statusText } }
      return NextResponse.json({ error: `Magento PUT ${res.status}`, magento: detail }, { status: 500 })
    }

    const magento = await res.json()
    return NextResponse.json({ success: true, magento })
  } catch (err: any) {
    return NextResponse.json({ error: err?.message ?? 'Unhandled error' }, { status: 500 })
  }
}
