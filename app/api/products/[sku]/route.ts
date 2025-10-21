export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const revalidate = 0
type M2Product = { sku?: string; custom_attributes?: Array<{attribute_code:string,value:any}>|null }
const ATTRS = ['ibu','ibu2','srm','hop_index','malt_index'] as const
export async function GET(_: Request, ctx: { params: { sku: string } }) {
  const { sku } = ctx.params
  const cfg = getMagentoConfig()
  const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
  const url = `${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
  if (!res.ok) return NextResponse.json({ error:`Magento GET ${res.status}`, detail: await res.text().catch(()=>res.statusText)}, { status: 500 })
  const data: M2Product = await res.json().catch(()=>({}))
  const ca = Array.isArray(data?.custom_attributes) ? data!.custom_attributes! : []
  const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))
  const lifted: Record<string, any> = {}
  for (const k of ATTRS) lifted[k] = attrs[k] ?? null
  return NextResponse.json({ ...(data||{}), ...lifted, _attrs: attrs })
}
