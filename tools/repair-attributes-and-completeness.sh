#!/usr/bin/env bash
set -euo pipefail
log(){ printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

BASE="${BASE:-http://localhost:3000}"

# 1) Ensure folders
mkdir -p app/api/products/attributes/[sku]

# 2) Dynamic attributes route (authoritative)
cat > app/api/products/attributes/[sku]/route.ts <<'TS'
import { NextResponse } from 'next/server'
import fs from 'node:fs/promises'
import path from 'node:path'

export async function GET(
  _req: Request,
  { params }: { params: { sku: string } }
) {
  const sku = decodeURIComponent(params.sku || '').trim()
  if (!sku) return NextResponse.json({ ok:false, error:'Missing sku' }, { status: 400 })

  // Attributes priority: var/attributes/<SKU>.json (overrides) → product.attributes
  const filePath = path.join(process.cwd(), 'var', 'attributes', `${sku}.json`)
  let fileAttrs: Record<string, any> = {}
  try {
    const buf = await fs.readFile(filePath)
    fileAttrs = JSON.parse(buf.toString())
  } catch { /* no local override file - fine */ }

  // Also surface merged product (if present)
  let product: any = null
  try {
    const r = await fetch(new URL(`/api/products/${encodeURIComponent(sku)}`, 'http://localhost'), { cache: 'no-store' })
    if (r.ok) product = await r.json()
  } catch { /* ignore */ }

  const merged: Record<string, any> = {
    ...(product?.attributes ?? {}),
    ...fileAttrs, // local file wins
  }

  return NextResponse.json({ ok:true, sku, attributes: merged })
}
TS

# 3) Fallback route: /api/products/attributes?sku=TEST → 307 /api/products/attributes/TEST
cat > app/api/products/attributes/route.ts <<'TS'
import { NextResponse } from 'next/server'

export async function GET(req: Request) {
  const url = new URL(req.url)
  const sku = (url.searchParams.get('sku') || '').trim()
  if (!sku) return NextResponse.json({ ok:false, error:'Missing sku' }, { status: 400 })
  return NextResponse.redirect(new URL(`/api/products/attributes/${encodeURIComponent(sku)}`, req.url), { status: 307 })
}
TS

# 4) Reinstall a known-good completeness route (your working version with family/channel/locale)
cat > app/api/products/completeness/route.ts <<'TS'
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
    const channel = q.get('channel') || 'ecommerce'
    const locale = q.get('locale') || 'nb_NO'

    // 1) krav pr familie
    const akeneo = await getJSON<any>(req, '/api/akeneo/attributes')
    const families: Record<string, { required: string[] }> = akeneo?.families || {}
    const DEFAULT_FAMILY = 'default'

    // 2) produkter (single eller bulk)
    let items: any[] = []
    if (sku) {
      const one = await getJSON<any>(req, `/api/products/${encodeURIComponent(sku)}`)
      if (one && one.sku) items = [one]
    } else {
      const merged = await getJSON<{ total:number, items:any[] }>(req, `/api/products/merged?page=${page}&size=${size}`)
      items = merged.items || []
    }

    // 3) completeness
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
      family: q.get('family') || DEFAULT_FAMILY,
      channel,
      locale,
      total: outItems.length,
      items: outItems
    })
  } catch (err: any) {
    return NextResponse.json({ ok:false, error: String(err?.message || err) }, { status: 500 })
  }
}
TS

# 5) Make sure there is no stray [id] left
find app -type d -path '*/products/[[]*[]]' -print | sed -n '/\[sku\]/!p' || true

# 6) Clear cache, restart dev, warm-up and verify
rm -rf .next
lsof -ti :3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
npm run dev --silent >/tmp/next-dev.log 2>&1 &
sleep 1

log "Warm-up health/merged…"
curl -fsS "$BASE/api/debug/health" >/dev/null 2>&1 || true
curl -fsS "$BASE/api/products/merged?page=1&size=1" >/dev/null 2>&1 || true

log "Verify: attributes (dynamic)"
curl -sS -D- "$BASE/api/products/attributes/TEST" -o /tmp/attr.json | head -n1 || true
file -b --mime-type /tmp/attr.json 2>/dev/null || true
head -c 160 /tmp/attr.json 2>/dev/null || true
echo

log "Verify: attributes fallback"
curl -sS -D- "$BASE/api/products/attributes?sku=TEST" -o /dev/null | head -n1 || true

log "Verify: completeness (single)"
curl -s "$BASE/api/products/completeness?sku=TEST" | jq -r '.items[0] | {sku,family,score:.completeness.score} // .'
