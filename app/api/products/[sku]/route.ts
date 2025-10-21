import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type CA = { attribute_code: string; value: any }
type M2Product = { sku?: string; custom_attributes?: CA[] | null }

const ALIASES = ['ibu','ibu2','srm','hop_index','malt_index'] as const

export async function GET(_: Request, ctx: { params: { sku: string } }) {
  const { sku } = ctx.params
  const cfg = getMagentoConfig()
  try {
    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
    const url = `${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0`
    const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
    const text = await res.text()
    let data: M2Product = {}
    try { data = text ? JSON.parse(text) : {} } catch { /* keep {} */ }

    if (!res.ok) {
      return NextResponse.json({ error: `Magento GET ${res.status}`, detail: text }, { status: 500 })
    }

    const ca = Array.isArray(data?.custom_attributes) ? data!.custom_attributes! : []
    const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))
    const lifted: Record<string, any> = {}
    for (const key of ALIASES) lifted[key] = attrs[key] ?? null
    // Prefer ibu if missing but ibu2 exists
    if (lifted['ibu'] == null && attrs['ibu2'] != null) lifted['ibu'] = attrs['ibu2']

    return NextResponse.json({ ...(data||{}), ...lifted, _attrs: attrs })
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Unhandled' }, { status: 500 })
  }
}
