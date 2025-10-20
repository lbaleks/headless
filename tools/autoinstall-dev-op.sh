# tools/autoinstall-dev-ops.sh (eller egen installer)
ensure_jobs_run_sync_route() {
  local F="app/api/jobs/run-sync/route.ts"
  if [ -f "$F" ]; then
    echo "  ✓ /api/jobs/run-sync finnes – hopper over."
    return
  fi
  echo "→ Installerer /api/jobs/run-sync (POST)…"
  mkdir -p "$(dirname "$F")"
  cat > "$F" <<'TS'
// app/api/jobs/run-sync/route.ts
import { NextResponse, NextRequest } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

export const dynamic = 'force-dynamic'
const VAR_DIR = path.join(process.cwd(), 'var')
const JOBS_FILE = path.join(VAR_DIR, 'jobs.json')
type Counts = { products: number; customers: number; orders: number }
type Job = { id:string; ts:string; type:'sync-all'; started:string; finished:string; counts:Counts }

async function readJobs(){ try{
  const j = JSON.parse(await fs.readFile(JOBS_FILE,'utf8'))
  return { total: j?.total ?? (Array.isArray(j?.items)? j.items.length:0), items: Array.isArray(j?.items)? j.items:[] }
}catch{ return { total:0, items:[] } } }
async function writeJobs(items:Job[]){ await fs.mkdir(VAR_DIR,{recursive:true}); await fs.writeFile(JOBS_FILE, JSON.stringify({ total: items.length, items }, null, 2)) }
function base(req:NextRequest){ const proto = req.headers.get('x-forwarded-proto') || (process.env.NODE_ENV==='production'?'https':'http'); const host = req.headers.get('host') || 'localhost:3000'; return `${proto}://${host}` }
async function postJSON<T=any>(url:string){ const r=await fetch(url,{method:'POST',headers:{'content-type':'application/json'},cache:'no-store'}); if(!r.ok){ throw new Error(`POST ${url} failed: ${r.status} ${await r.text().catch(()=> '')}`) } return await r.json().catch(()=> ({} as T)) }

export async function POST(req:NextRequest){
  const started = new Date()
  const b = base(req)
  const prod = await postJSON<{ok:boolean;saved?:number}>(`${b}/api/products/sync`).catch(()=>({ok:false,saved:0}))
  const cust = await postJSON<{ok:boolean;saved?:number}>(`${b}/api/customers/sync`).catch(()=>({ok:false,saved:0}))
  const orde = await postJSON<{ok:boolean;saved?:number}>(`${b}/api/orders/sync`).catch(()=>({ok:false,saved:0}))
  const counts:Counts = { products:Number(prod.saved??0), customers:Number(cust.saved??0), orders:Number(orde.saved??0) }
  const job:Job = { id:`JOB-${Date.now()}`, ts:new Date().toISOString(), type:'sync-all', started: started.toString(), finished: new Date().toString(), counts }
  const prev = await readJobs()
  await writeJobs([job, ...prev.items])
  return NextResponse.json({ id: job.id, counts })
}
TS
  echo "  ✓ Opprettet $F"
}

# kall funksjonen et passende sted:
ensure_jobs_run_sync_route