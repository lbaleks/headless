export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { m2 } from '@/lib/magento'

export async function GET() {
  const out:any = { base: m2.BASE, tokenPrefix: (process.env.MAGENTO_ADMIN_TOKEN||'').slice(0,6) + '…', checks: [] }
  // Best-effort: ordrer, produkter, kunder
  const endpoints = [
    { name: 'orders',    url: 'V1/orders?searchCriteria[pageSize]=1' },
    { name: 'products',  url: 'V1/products?searchCriteria[pageSize]=1' },
    { name: 'customers', url: 'V1/customers/search?searchCriteria[pageSize]=1' },
  ]
  for (const ep of endpoints) {
    try {
      const data = await m2.get<any>(ep.url)
      out.checks.push({ ok: true, status: 200, url: `${m2.BASE}/${ep.url}`, sample: Array.isArray(data?.items) ? {items:data.items.slice(0,1), total_count:data.total_count} : data })
    } catch (e:any) {
      out.checks.push({ ok: false, status: e?.message?.match(/\s(\d{3})\s/)?Number(RegExp.$1):0, url: `${m2.BASE}/${ep.url}`, sample: String(e?.message||e) })
    }
  }
  return NextResponse.json(out)
}
