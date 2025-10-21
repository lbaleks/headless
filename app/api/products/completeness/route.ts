export const runtime = 'nodejs';
export const revalidate = 0
export const dynamic = 'force-dynamic'
import { NextResponse } from 'next/server'

type AttrMap = Record<string, any>
type Families = Record<string, { required: string[] }>

async function getJSON<T>(absoluteUrl: string): Promise<T> {
  const r = await fetch(absoluteUrl, { cache: 'no-store' })
  if (!r.ok) throw new Error(`${absoluteUrl} -> ${r.status}`)
  return r.json() as Promise<T>
}

export async function GET(req: Request) {
  const url = new URL(req.url)
  const origin = `${url.protocol}//${url.host}`

  const q = url.searchParams
  const sku = q.get('sku') || ''
  const page = Number(q.get('page') || 1)
  const size = Number(q.get('size') || 50)
  const channel = q.get('channel') || 'ecommerce'
  const locale  = q.get('locale')  || 'nb_NO'
  const DEFAULT_FAMILY = 'default'

  const diagnostics: any = {}

  try {
    // 1) families / required attributes per family
    let families: Families = {}
    try {
      const akeneo = await getJSON<any>(`${origin}/api/akeneo/attributes`)
      families = akeneo?.families || {}
    } catch (e:any) {
      diagnostics.akeneo = String(e?.message || e)
      families = { [DEFAULT_FAMILY]: { required: ['sku','name','price','status','visibility'] } }
    }

    // 2) collect items (single or bulk)
    let items: any[] = []
    if (sku) {
      try {
        const one = await getJSON<any>(`${origin}/api/products/${encodeURIComponent(sku)}`)
        if (one && one.sku) items = [one]
        else diagnostics.single = 'product returned without sku'
      } catch (e:any) {
        diagnostics.single = String(e?.message || e)
      }
    } else {
      try {
        const merged = await getJSON<{ total:number, items:any[] }>(`${origin}/api/products/merged?page=${page}&size=${size}`)
        items = merged?.items || []
      } catch (e:any) {
        diagnostics.bulk = String(e?.message || e)
        items = []
      }
    }

    // 3) compute completeness per item
    const makeHas = (item: any) => {
      const attrs: AttrMap = item?.attributes || {}
      return (key: string) => {
        const v = (key in attrs) ? attrs[key] : item?.[key]
        if (v === null || v === undefined) return false
        if (typeof v === 'string') return v.trim().length > 0
        return true
      }
    }

    const outItems = items.map((item) => {
      const fam = String(item?.family ?? item?.attributes?.family ?? DEFAULT_FAMILY)
      const required = families[fam]?.required ?? families[DEFAULT_FAMILY]?.required ?? ['sku','name','price','status','visibility']
      const has = makeHas(item)
      const missing = required.filter((k) => !has(k))
      const score = required.length ? Math.round((required.length - missing.length) / required.length * 100) : 100
      return {
        sku: item?.sku ?? null,
        name: item?.name ?? null,
        family: fam,
        channel,
        locale,
        completeness: { score, missing, required }
      }
    })

    return NextResponse.json({
      ok: true,
      family: q.get('family', { headers: { 'Cache-Control': 'no-store' } }) || DEFAULT_FAMILY,
      channel,
      locale,
      total: outItems.length,
      items: outItems,
      ...(Object.keys(diagnostics).length ? { diagnostics } : {})
    })
  } catch (err: any) {
    return NextResponse.json({ ok:false, error: String(err?.message || err, { headers: { 'Cache-Control': 'no-store' } }) }, { status: 500 })
  }
}
