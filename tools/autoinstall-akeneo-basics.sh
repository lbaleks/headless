#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="$ROOT/app/api"
SRC="$ROOT/src"
VAR="$ROOT/var"

echo "→ Akeneo-basics autoinstaller…"

mkdir -p "$ROOT/config/families" "$SRC/lib" \
         "$API/products/completeness" "$API/products/bulk" "$API/jobs" \
         "$VAR/audit" "$VAR"

# -------------------------------------------------------------------
# A) Families (krav) + enkel config
# -------------------------------------------------------------------
FAM="$ROOT/config/families/default.json"
if [ ! -f "$FAM" ]; then
  cat > "$FAM" <<'JSON'
{
  "code": "default",
  "label": "Default family",
  "required_attributes": ["sku","name","price","status","visibility"],
  "optional_attributes": ["image","tax_class_id"],
  "channels": [
    { "code": "web", "locales": ["nb_NO","en_GB"] },
    { "code": "pos", "locales": ["nb_NO"] }
  ]
}
JSON
  echo "  • Skrev config/families/default.json"
else
  echo "  • config/families/default.json finnes – hopper over"
fi

# -------------------------------------------------------------------
# B) completeness.ts – beregn fullføringsgrad
# -------------------------------------------------------------------
COMP="$SRC/lib/completeness.ts"
if [ ! -f "$COMP" ]; then
  cat > "$COMP" <<'TS'
export type Family = {
  code: string
  label?: string
  required_attributes: string[]
  optional_attributes?: string[]
  channels?: { code: string; locales: string[] }[]
}

export function computeCompleteness(
  product: Record<string, any>,
  family: Family
){
  const required = family.required_attributes || []
  const missing: string[] = []
  for(const key of required){
    const v = (product as any)[key]
    const empty = v === null || v === undefined || v === '' || (typeof v==='number' && Number.isNaN(v))
    if (empty) missing.push(key)
  }
  const score = required.length === 0 ? 100 : Math.round(100 * (required.length - missing.length) / required.length)
  return { score, missing, required }
}
TS
  echo "  • Skrev src/lib/completeness.ts"
else
  echo "  • src/lib/completeness.ts finnes – hopper over"
fi

# -------------------------------------------------------------------
# C) /api/products/completeness – GET liste m/score
# -------------------------------------------------------------------
ROUTE_COMP="$API/products/completeness/route.ts"
if [ ! -f "$ROUTE_COMP" ]; then
  cat > "$ROUTE_COMP" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'
import { computeCompleteness } from '@/src/lib/completeness'

const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')

async function readFamily(){
  const file = path.join(process.cwd(), 'config', 'families', 'default.json')
  try{ return JSON.parse(await fs.readFile(file,'utf8')) }catch{ return { code:'default', required_attributes: [] } }
}
export async function GET(req:Request){
  const url = new URL(req.url)
  const page = Math.max(1, Number(url.searchParams.get('page')||'1'))
  const size = Math.max(1, Number(url.searchParams.get('size')||'50'))
  const q    = (url.searchParams.get('q')||'').toLowerCase()

  // hent “merged” fra egen API for å respektere Magento + overrides
  const base = url.origin
  const merged = await fetch(`${base}/api/products?` + url.searchParams.toString(), { cache:'no-store' })
  const data = await merged.json().catch(()=>({ total:0, items:[] }))
  const fam = await readFamily()

  let items:any[] = Array.isArray(data.items) ? data.items : []
  if (q) items = items.filter(p => (p.sku||'').toLowerCase().includes(q) || (p.name||'').toLowerCase().includes(q))

  const start = (page-1)*size, end = start+size
  const pageItems = items.slice(start, end).map(p => {
    const c = computeCompleteness(p, fam)
    return { ...p, completeness: c }
  })
  return NextResponse.json({ total: items.length, items: pageItems, family: fam.code })
}
TS
  echo "  • La til /api/products/completeness"
else
  echo "  • /api/products/completeness finnes – hopper over"
fi

# -------------------------------------------------------------------
# D) Audit helper – append jsonl per SKU
# -------------------------------------------------------------------
AUD="$SRC/lib/audit.ts"
if [ ! -f "$AUD" ]; then
  cat > "$AUD" <<'TS'
import fs from 'fs'
import path from 'path'

export function auditProductChange(sku:string, before:any, after:any){
  try{
    const dir = path.join(process.cwd(), 'var', 'audit')
    fs.mkdirSync(dir, { recursive:true })
    const line = JSON.stringify({ ts: new Date().toISOString(), sku, before, after }) + '\n'
    fs.appendFileSync(path.join(dir, `products.${sku}.jsonl`), line)
  }catch{/* best effort */}
}
TS
  echo "  • Skrev src/lib/audit.ts"
else
  echo "  • src/lib/audit.ts finnes – hopper over"
fi

# -------------------------------------------------------------------
# E) Bulk-edit endpoint
# -------------------------------------------------------------------
BULK="$API/products/bulk/route.ts"
if [ ! -f "$BULK" ]; then
  cat > "$BULK" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'
import { auditProductChange } from '@/src/lib/audit'

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
function idx(items:any[], sku:string){ return items.findIndex(p => String(p.sku).toLowerCase()===sku.toLowerCase()) }

export async function PATCH(req:Request){
  const body = await req.json().catch(()=>null)
  if(!body || !Array.isArray(body.items)) return NextResponse.json({ ok:false, error:'Expect {items:[{sku, changes:{...}}]}' }, { status:400 })
  const items = await readLocal()
  let updated = 0
  for(const row of body.items){
    const sku = String(row.sku||'')
    const changes = row.changes && typeof row.changes==='object' ? row.changes : {}
    if(!sku || !Object.keys(changes).length) continue
    let i = idx(items, sku)
    if(i===-1){
      const obj = { sku, ...changes, created_at:new Date().toISOString(), updated_at:new Date().toISOString(), source:'local-override' }
      items.push(obj); i = items.length-1
      auditProductChange(sku, null, obj)
      updated++
    }else{
      const before = items[i]
      items[i] = { ...items[i], ...changes, updated_at:new Date().toISOString(), source: items[i].source || 'local-override' }
      auditProductChange(sku, before, items[i])
      updated++
    }
  }
  await writeLocal(items)
  return NextResponse.json({ ok:true, updated })
}
TS
  echo "  • La til /api/products/bulk (PATCH)"
else
  echo "  • /api/products/bulk finnes – hopper over"
fi

# -------------------------------------------------------------------
# F) Jobs-logg (GET/POST) + wrapper script
# -------------------------------------------------------------------
JOBS="$API/jobs/route.ts"
if [ ! -f "$JOBS" ]; then
  cat > "$JOBS" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'
const FILE = path.join(process.cwd(), 'var', 'jobs.json')

async function read(){ try{ return JSON.parse(await fs.readFile(FILE,'utf8')) }catch{ return [] } }
async function write(arr:any[]){ await fs.mkdir(path.dirname(FILE),{recursive:true}); await fs.writeFile(FILE, JSON.stringify(arr,null,2)) }

export async function GET(){ const arr = await read(); return NextResponse.json({ total: arr.length, items: arr.slice(-50).reverse() }) }

export async function POST(req:Request){
  const body = await req.json().catch(()=>({}))
  const arr = await read()
  const now = new Date().toISOString()
  const rec = { id: 'JOB-'+Date.now(), ts: now, ...body }
  arr.push(rec); await write(arr)
  return NextResponse.json(rec)
}
TS
  echo "  • La til /api/jobs"
else
  echo "  • /api/jobs finnes – hopper over"
fi

WRAP="$ROOT/tools/sync-with-jobs.sh"
cat > "$WRAP" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:3000}"
start=$(date -Iseconds)
p=$(curl -s -X POST "$BASE/api/products/sync" | jq -r '.saved // 0')
c=$(curl -s -X POST "$BASE/api/customers/sync" | jq -r '.saved // 0')
o=$(curl -s -X POST "$BASE/api/orders/sync"   | jq -r '.saved // 0')
end=$(date -Iseconds)
curl -s -X POST "$BASE/api/jobs" -H 'content-type: application/json' \
  --data "{\"type\":\"sync-all\",\"started\":\"$start\",\"finished\":\"$end\",\"counts\":{\"products\":$p,\"customers\":$c,\"orders\":$o}}" | jq .
SH
chmod +x "$WRAP"
echo "  • Skrev tools/sync-with-jobs.sh"

echo "✓ Ferdig. Restart dev (Ctrl+C → npm run dev) og verifiser:"
echo "  1) Completeness liste:"
echo "     curl -s 'http://localhost:3000/api/products/completeness?page=1&size=5' | jq '.items[0].sku,.items[0].completeness'"
echo "  2) Bulk edit 2 produkter:"
echo "     jq -n '{items:[{sku:\"TEST\",changes:{price:599}},{sku:\"SEED-EXAMPLE\",changes:{status:1}}]}' \\"
echo "        | curl -s -X PATCH 'http://localhost:3000/api/products/bulk' -H 'content-type: application/json' --data-binary @- | jq ."
echo "  3) Kjør sync med jobblogg:"
echo "     tools/sync-with-jobs.sh"
echo "     curl -s 'http://localhost:3000/api/jobs' | jq '.items[0]'"