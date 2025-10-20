#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
say(){ printf "→ %s\n" "$*"; }
ensure(){ mkdir -p "$1"; }

# 1) /api/jobs (index) — reinstaller hvis mangler
say "Sikrer /api/jobs…"
ensure "$ROOT/app/api/jobs"
if [ ! -f "$ROOT/app/api/jobs/route.ts" ]; then
  cat > "$ROOT/app/api/jobs/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'
const JOBS_DIR = path.join(process.cwd(), 'var', 'jobs')
export async function GET() {
  try{
    await fs.mkdir(JOBS_DIR, { recursive: true })
    const files = (await fs.readdir(JOBS_DIR)).filter(f=>f.endsWith('.json')).sort().reverse()
    const items = []
    for (const f of files) {
      try{ items.push(JSON.parse(await fs.readFile(path.join(JOBS_DIR, f),'utf8'))) }catch{}
    }
    return NextResponse.json({ total: items.length, items })
  }catch(e:any){
    return NextResponse.json({ ok:false, error:String(e) }, { status:500 })
  }
}
TS
fi

# 2) /api/jobs/run-sync — kjører sync og skriver job-json
say "Sikrer /api/jobs/run-sync…"
ensure "$ROOT/app/api/jobs/run-sync"
cat > "$ROOT/app/api/jobs/run-sync/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const JOBS_DIR = path.join(process.cwd(), 'var', 'jobs')

async function post(url:string){
  const r = await fetch(url, { method:'POST', cache:'no-store' })
  if(!r.ok) throw new Error(`HTTP ${r.status} ${url}`)
  return r.json().catch(()=>({}))
}

export async function POST(){
  const origin = process.env.NEXT_PUBLIC_BASE_URL || 'http://localhost:3000'
  const started = new Date()
  const id = `JOB-${Date.now()}`
  const job = { id, ts: started.toISOString(), type:'sync-all', started: started.toString(), finished:null, counts:{} as any }
  try{
    const products  = await post(`${origin}/api/products/sync`)
    const customers = await post(`${origin}/api/customers/sync`)
    const orders    = await post(`${origin}/api/orders/sync`)
    job.counts = {
      products:  Number(products?.saved ?? products?.total ?? 0),
      customers: Number(customers?.saved ?? customers?.total ?? 0),
      orders:    Number(orders?.saved ?? orders?.total ?? 0),
    }
  }catch(e:any){
    job.counts = { products:0, customers:0, orders:0, error:String(e) }
  }
  job.finished = new Date().toString()
  await fs.mkdir(JOBS_DIR, { recursive:true })
  await fs.writeFile(path.join(JOBS_DIR, `${id}.json`), JSON.stringify(job,null,2))
  return NextResponse.json(job)
}
TS

# 3) /api/audit/products/[sku]
say "Sikrer /api/audit/products/[sku]…"
ensure "$ROOT/app/api/audit/products/[sku]"
cat > "$ROOT/app/api/audit/products/[sku]/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'
const AUD_DIR = path.join(process.cwd(), 'var', 'audit')
export async function GET(_:Request, ctx:{params:{sku:string}}){
  const sku = decodeURIComponent(ctx.params.sku)
  const file = path.join(AUD_DIR, `products.${sku}.jsonl`)
  try{
    const txt = await fs.readFile(file,'utf8')
    const lines = txt.trim().split(/\r?\n/).filter(Boolean).map(l=>JSON.parse(l))
    return NextResponse.json({ total: lines.length, items: lines })
  }catch{
    return NextResponse.json({ total: 0, items: [] })
  }
}
TS

# 4) /api/products/completeness — bruk request.origin, ikke tom base
say "Patch /api/products/completeness…"
ensure "$ROOT/app/api/products/completeness"
cat > "$ROOT/app/api/products/completeness/route.ts" <<'TS'
import { NextResponse, NextRequest } from 'next/server'
const REQUIRED = ['sku','name','price','status','visibility']
async function getJson(url:string){
  const r = await fetch(url, { cache:'no-store' })
  if(!r.ok) throw new Error(`HTTP ${r.status} for ${url}`)
  return r.json()
}
export async function GET(req:NextRequest){
  const page = Number(req.nextUrl.searchParams.get('page')||1)
  const size = Number(req.nextUrl.searchParams.get('size')||20)
  const q    = req.nextUrl.searchParams.get('q') || ''
  const origin = req.nextUrl.origin || process.env.NEXT_PUBLIC_BASE_URL || 'http://localhost:3000'
  const url = `${origin}/api/products/merged?page=${page}&size=${size}${q?`&q=${encodeURIComponent(q)}`:''}`
  try{
    const data = await getJson(url)
    const items = (data.items||[]).map((p:any)=>{
      const missing = REQUIRED.filter(k => p[k]==null || p[k]==='' || (k==='price' && Number(p[k])<=0))
      const score = Math.round(100 * (REQUIRED.length - missing.length) / REQUIRED.length)
      return { sku:p.sku, name:p.name, completeness:{ score, missing, required: REQUIRED } }
    })
    return NextResponse.json({ family:'default', items })
  }catch(e:any){
    return NextResponse.json({ ok:false, error:String(e) }, { status:500 })
  }
}
TS

echo "OK"
