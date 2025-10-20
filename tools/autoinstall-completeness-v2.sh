#!/usr/bin/env bash
set -euo pipefail
base="app/api/products/completeness"
mkdir -p "$base"
cat > "$base/route.ts" <<'TS'
import { NextResponse } from 'next/server'
type AttrMap = Record<string, any>
async function getJSON<T>(req: Request, pathname: string): Promise<T> {
  const url = new URL(pathname, req.url)
  const r = await fetch(url, { cache: 'no-store' })
  if (!r.ok) throw new Error(`Failed ${pathname}: ${r.status}`)
  return r.json() as Promise<T>
}
export async function GET(req: Request) {
  try {
    const q = new URL(req.url).searchParams
    const sku = q.get('sku') || ''
    const page = Number(q.get('page') || 1)
    const size = Number(q.get('size') || 50)
    const akeneo = await getJSON<any>(req, '/api/akeneo/attributes')
    const families: Record<string, { required: string[] }> = akeneo?.families || {}
    const DEFAULT_FAMILY = 'default'
    let items: any[] = []
    if (sku) {
      const one = await getJSON<any>(req, `/api/products/${encodeURIComponent(sku)}`)
      if (one && one.sku) items = [one]
    } else {
      const merged = await getJSON<{ total:number, items:any[] }>(req, `/api/products/merged?page=${page}&size=${size}`)
      items = merged.items || []
    }
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
      return { sku:item?.sku ?? null, name:item?.name ?? null, family:fam, channel:'ecommerce', locale:'nb_NO',
        completeness:{ score, missing, required } }
    })
    return NextResponse.json({ family:q.get('family')||DEFAULT_FAMILY, channel:'ecommerce', locale:'nb_NO', total:outItems.length, items:outItems })
  } catch (err:any) {
    return NextResponse.json({ ok:false, error:String(err?.message||err) }, { status: 500 })
  }
}
TS
# røyk-test
sleep 0.3
curl -s 'http://localhost:3000/api/products/completeness?sku=TEST' \
  | jq -e '.items[0].completeness.score == 100' >/dev/null && echo "Completeness v2 OK" || (echo "Completeness v2 FAIL"; exit 1)
