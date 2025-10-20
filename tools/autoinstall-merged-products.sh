#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
api_dir="$root_dir/app/api"
prod_dir="$api_dir/products"
merged_dir="$prod_dir/merged"
seed_dir="$prod_dir/seed"
route_ts="$prod_dir/route.ts"
merged_route_ts="$merged_dir/route.ts"
seed_route_ts="$seed_dir/route.ts"
env_file="$root_dir/.env.local"
next_config="$root_dir/next.config.js"

echo "→ Autoinstaller (merged products + seed)"

# 0) Sjekk at app/api finnes
mkdir -p "$prod_dir" "$merged_dir" "$seed_dir"

# 1) .env.local: USE_MERGED_PRODUCTS=1
if ! grep -q '^USE_MERGED_PRODUCTS=' "$env_file" 2>/dev/null; then
  echo "USE_MERGED_PRODUCTS=1" >> "$env_file"
  echo "  • Skrev USE_MERGED_PRODUCTS=1 til .env.local"
else
  # sett til 1 hvis ikke allerede 1
  perl -0777 -pe 's/^USE_MERGED_PRODUCTS=.*/USE_MERGED_PRODUCTS=1/m' -i "$env_file" || \
  sed -i '' 's/^USE_MERGED_PRODUCTS=.*/USE_MERGED_PRODUCTS=1/' "$env_file"
  echo "  • Oppdatert USE_MERGED_PRODUCTS=1 i .env.local"
fi

# 2) /api/products/merged (returnerer kombinasjon av Magento + lokale overrides/seed)
if [ ! -f "$merged_route_ts" ]; then
  cat > "$merged_route_ts" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json') // overrides/seed lagres her
const M2_BASE  = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || ''
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || ''

async function readLocal(): Promise<any[]> {
  try {
    const txt = await fs.readFile(DEV_FILE, 'utf8')
    const j = JSON.parse(txt)
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch {
    return []
  }
}

function likeStr(x:string){ return (x||'').toLowerCase() }
function matchesQ(p:any, q:string){
  if(!q) return true
  const s = likeStr(q)
  return likeStr(p.sku||'').includes(s) || likeStr(p.name||'').includes(s)
}

function mapM2(p:any){
  const get = (code:string)=> (p.custom_attributes||[]).find((a:any)=>a.attribute_code===code)?.value
  return {
    id: p.id,
    sku: p.sku,
    name: p.name,
    type: p.type_id,
    price: Number(p.price ?? 0),
    status: p.status,
    visibility: p.visibility,
    created_at: p.created_at,
    updated_at: p.updated_at,
    image: get('image') || null,
    tax_class_id: get('tax_class_id') || null,
    has_options: Boolean(p.options?.length || p.required_options),
    required_options: Boolean(p.required_options),
    source: 'magento',
  }
}

export async function GET(req: Request) {
  const url = new URL(req.url)
  const page = Math.max(1, Number(url.searchParams.get('page')||'1'))
  const size = Math.max(1, Number(url.searchParams.get('size')||'20'))
  const q    = (url.searchParams.get('q')||'').trim()

  // 1) Magento
  let magentoItems:any[] = []
  if (M2_BASE && M2_TOKEN) {
    const m2url = `${M2_BASE.replace(/\/+$/,'')}/V1/products?searchCriteria[pageSize]=200`
    const r = await fetch(m2url, { headers: { Authorization:`Bearer ${M2_TOKEN}` }, cache:'no-store' })
    const j = await r.json().catch(()=>null)
    if (r.ok && j && Array.isArray(j.items)) {
      magentoItems = j.items.map(mapM2)
    }
  }

  // 2) Lokalt (overrides/seed)
  const local = await readLocal()

  // 3) Merge: lokale ting vinner på SKU
  const bySku = new Map<string, any>()
  for (const p of magentoItems) bySku.set(String(p.sku).toLowerCase(), p)
  for (const p of local)       bySku.set(String(p.sku).toLowerCase(), { ...bySku.get(String(p.sku).toLowerCase()), ...p, source: 'local-override' })

  let items = Array.from(bySku.values())
  if (q) items = items.filter(p => matchesQ(p, q))

  const total = items.length
  const start = (page-1)*size
  const end   = start+size
  const pageItems = items.slice(start, end)

  return NextResponse.json({ total, items: pageItems, source: 'magento+local' })
}
TS
  echo "  • Opprettet /api/products/merged (Next.js route)"
else
  echo "  • /api/products/merged finnes – hopper over"
fi

# 3) /api/products/seed (POST n=5, GET liste fra local store)
if [ ! -f "$seed_route_ts" ]; then
  cat > "$seed_route_ts" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')

async function readLocal(): Promise<any[]> {
  try {
    const txt = await fs.readFile(DEV_FILE, 'utf8')
    const j = JSON.parse(txt)
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch { return [] }
}
async function writeLocal(items:any[]){
  await fs.mkdir(path.dirname(DEV_FILE), { recursive: true })
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}

export async function GET() {
  const items = await readLocal()
  return NextResponse.json({ total: items.length, items })
}

function mk(i:number, base=Date.now()){
  return {
    id: 100000 + i,
    sku: `SEED-${base}-${i}`,
    name: `Seed Product ${i}`,
    type: 'simple',
    price: 200 + i,
    status: 1,
    visibility: 4,
    created_at: new Date(base).toISOString(),
    updated_at: new Date(base).toISOString(),
    image: null,
    tax_class_id: '2',
    has_options: false,
    required_options: false,
    source: 'local-stub',
  }
}

export async function POST(req:Request) {
  const url = new URL(req.url)
  const n = Math.max(1, Number(url.searchParams.get('n')||'5'))
  const items = await readLocal()
  const base = Date.now()
  for (let i=1;i<=n;i++) items.unshift(mk(i, base))
  await writeLocal(items)
  return NextResponse.json({ ok:true, total: items.length })
}
TS
  echo "  • Opprettet /api/products/seed (Next.js route)"
else
  echo "  • /api/products/seed finnes – hopper over"
fi

# 4) /api/products (proxy til merged når USE_MERGED_PRODUCTS=1)
cat > "$route_ts" <<'TS'
import { NextResponse } from 'next/server'

export async function GET(req: Request) {
  const url = new URL(req.url)
  const merged = process.env.USE_MERGED_PRODUCTS === '1'
  const path = merged ? '/api/products/merged' : '/api/products/magento'
  const proxied = await fetch(new URL(path + '?' + url.searchParams.toString(), url.origin), { cache: 'no-store' })
  const json = await proxied.json().catch(()=>({ok:false,error:'Bad JSON from proxy'}))
  return NextResponse.json(json, { status: proxied.status })
}
TS
echo "  • /api/products -> proxy (merged når USE_MERGED_PRODUCTS=1)"

# 5) Optional rewrite (hvis du foretrekker rewrite over proxy)
if [ ! -f "$next_config" ]; then
  cat > "$next_config" <<'JS'
/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    const merged = process.env.USE_MERGED_PRODUCTS === '1'
    return merged ? [{ source: '/api/products', destination: '/api/products/merged' }] : []
  },
}
module.exports = nextConfig
JS
  echo "  • Skrev minimal next.config.js med rewrite støtte"
else
  echo "  • next.config.js finnes – beholdes som er (proxyen fungerer uansett)"
fi

echo "✓ Ferdig. Restart dev-serveren (Ctrl+C → npm run dev) og verifiser:"
echo "  curl -s 'http://localhost:3000/api/products?page=1&size=5' | jq '.total,(.items[0]//{}),.source'"
echo "  curl -s 'http://localhost:3000/api/products?page=1&size=5&q=SEED-' | jq '.total'"
echo "  curl -s -X POST 'http://localhost:3000/api/products/seed?n=5' | jq ."