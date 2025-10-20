#!/usr/bin/env bash
set -euo pipefail

ROOT="${PWD}"

# ---------- helpers ----------
ensure_dir() { mkdir -p "$1"; }
write_file() { # $1=path, stdin=content
  tmp="$(mktemp)"; cat - > "$tmp"; mkdir -p "$(dirname "$1")"; mv "$tmp" "$1"
  echo "  ✓ wrote $1"
}

# ---------- 1) /api/products/seed (GET + POST) ----------
ensure_dir app/api/products/seed

write_file app/api/products/seed/route.ts <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')

async function readStore(): Promise<any[]> {
  try {
    const txt = await fs.readFile(DEV_FILE, 'utf8')
    const j = JSON.parse(txt)
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch { return [] }
}

async function writeStore(items: any[]) {
  await fs.mkdir(path.dirname(DEV_FILE), { recursive: true })
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}

function now() { return new Date().toISOString() }
function mkSeed(i:number) {
  const id = 100000 + i
  return {
    id,
    sku: `SEED-${Date.now()}-${i}`,
    name: `Seed produkt ${i}`,
    type: 'simple',
    price: 199 + (i * 10),
    status: 1,
    visibility: 4,
    created_at: now(),
    updated_at: now(),
    image: null,
    tax_class_id: '2',
    has_options: false,
    required_options: false,
    source: 'local-override'
  }
}

export async function GET() {
  const items = await readStore()
  return NextResponse.json({ ok:true, total: items.length, items })
}

// Idempotent: append n seed-produkt til var/products.dev.json
export async function POST(req: Request) {
  const { searchParams } = new URL(req.url)
  const n = Math.max(1, Math.min(100, Number(searchParams.get('n') || 5)))

  const items = await readStore()
  const seeds = Array.from({ length: n }, (_, i) => mkSeed(i+1))
  const merged = [...seeds, ...items]
  await writeStore(merged)

  return NextResponse.json({ ok: true, total: merged.length })
}
TS

echo "→ Installed /api/products/seed (GET+POST)"

# ---------- 2) /api/products/merged (GET) ----------
ensure_dir app/api/products/merged

write_file app/api/products/merged/route.ts <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')
const M2_BASE  = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || ''
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || ''

async function readLocal(): Promise<any[]> {
  try {
    const txt = await fs.readFile(DEV_FILE, 'utf8')
    const j = JSON.parse(txt)
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch { return [] }
}

function normSku(x:any){ return String(x?.sku ?? '').toLowerCase() }

function mapM2(p:any){
  if(!p) return null
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
    has_options: Boolean(p.options?.length || p.required_options || get('has_options') === '1'),
    required_options: Boolean(p.required_options || get('required_options') === '1'),
    source: 'magento'
  }
}

async function fetchMagentoList(limit=250): Promise<{ok:boolean; items:any[]; status:number; detail?:any}>{
  if(!M2_BASE || !M2_TOKEN) return { ok:false, items:[], status:400, detail:'missing MAGENTO_BASE_URL / MAGENTO_ADMIN_TOKEN' }
  const url = `${M2_BASE.replace(/\/+$/,'')}/V1/products?searchCriteria[pageSize]=${limit}`
  const r = await fetch(url, { headers:{ Authorization:`Bearer ${M2_TOKEN}` }, cache:'no-store' })
  const js = await r.json().catch(()=>null)
  if(!r.ok) return { ok:false, items:[], status:r.status, detail:js }
  const items = Array.isArray(js?.items) ? js.items.map(mapM2).filter(Boolean) : []
  return { ok:true, items, status:r.status }
}

function overlay(mag:any[], local:any[]){
  const bySku = new Map<string, any>()
  for(const m of mag) bySku.set(normSku(m), { ...m })
  for(const loc of local){
    const k = normSku(loc)
    if(bySku.has(k)) bySku.set(k, { ...bySku.get(k), ...loc })
    else bySku.set(k, loc)
  }
  return Array.from(bySku.values())
}

export async function GET(req: Request){
  const { searchParams } = new URL(req.url)
  const page = Math.max(1, Number(searchParams.get('page') || 1))
  const size = Math.max(1, Math.min(100, Number(searchParams.get('size') || 20)))
  const q = (searchParams.get('q') || '').toLowerCase().trim()

  const local = await readLocal()
  const mag = await fetchMagentoList(250)
  let merged = overlay(mag.ok ? mag.items : [], local)

  if(q){
    merged = merged.filter(p =>
      String(p.sku ?? '').toLowerCase().includes(q) ||
      String(p.name ?? '').toLowerCase().includes(q)
    )
  }

  merged.sort((a,b)=>{
    const aa = new Date(a.updated_at ?? a.created_at ?? 0).getTime()
    const bb = new Date(b.updated_at ?? b.created_at ?? 0).getTime()
    if (aa && bb && aa !== bb) return bb - aa
    return String(a.sku ?? '').localeCompare(String(b.sku ?? ''))
  })

  const total = merged.length
  const start = (page-1) * size
  const items = merged.slice(start, start+size)

  return NextResponse.json({ total, items, source: mag.ok ? 'magento+local' : 'local-only' })
}
TS

echo "→ Installed /api/products/merged (GET)"

echo "✓ Autoinstall complete."
