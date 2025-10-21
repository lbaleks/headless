export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const revalidate = 0
type M2Product = { sku?: string; custom_attributes?: Array<{attribute_code:string,value:any}>|null }
const ATTRS = ['ibu','ibu2','srm','hop_index','malt_index'] as const
export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = Number(searchParams.get('page')||'1')||1
  const size = Number(searchParams.get('size')||'50')||50
  const cfg = getMagentoConfig()
  const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
  const url = `${v1(cfg.baseUrl)}/products?searchCriteria[current_page]=${page}&searchCriteria[page_size]=${size}&storeId=0`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
  if (!res.ok) return NextResponse.json({ error:`Magento GET ${res.status}`, detail: await res.text().catch(()=>res.statusText)}, { status: 500 })
  const data = await res.json().catch(()=>({}))
  const items: M2Product[] = Array.isArray(data?.items) ? data.items : []
  const lifted = items.map(p => {
    const ca = Array.isArray(p?.custom_attributes) ? p!.custom_attributes! : []
    const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))
    const out: Record<string, any> = {}
    for (const k of ATTRS) out[k] = attrs[k] ?? null
    return { ...(p||{}), ...out, _attrs: attrs }
  })
  return NextResponse.json({ items: lifted, page, size, total: data?.total_count ?? lifted.length })
}
