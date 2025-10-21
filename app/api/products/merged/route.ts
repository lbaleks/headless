import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type CA = { attribute_code: string; value: any }
type M2Product = { sku?: string; custom_attributes?: CA[] | null }

const ALIASES = ['ibu','ibu2','srm','hop_index','malt_index'] as const

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = Number(searchParams.get('page')||'1')||1
  const size = Number(searchParams.get('size')||'50')||50
  const cfg = getMagentoConfig()

  try {
    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
    const url = `${v1(cfg.baseUrl)}/products?searchCriteria[current_page]=${page}&searchCriteria[page_size]=${size}&storeId=0`
    const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
    const text = await res.text()
    const data = text ? JSON.parse(text) : {}
    if (!res.ok) {
      return NextResponse.json({ error: `Magento GET ${res.status}`, detail: data ?? text }, { status: 500 })
    }

    const items: M2Product[] = Array.isArray(data?.items) ? data.items : []
    const lifted = items.map(p => {
      const ca = Array.isArray(p?.custom_attributes) ? p!.custom_attributes! : []
      const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))
      const out: Record<string, any> = {}
      for (const k of ALIASES) out[k] = attrs[k] ?? null
      if (out['ibu'] == null && attrs['ibu2'] != null) out['ibu'] = attrs['ibu2']
      return { ...(p||{}), ...out, _attrs: attrs }
    })

    return NextResponse.json({ items: lifted, page, size, total: data?.total_count ?? lifted.length })
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Unhandled' }, { status: 500 })
  }
}
