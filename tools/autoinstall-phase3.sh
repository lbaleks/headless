# tools/autoinstall-phase3.sh
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say(){ printf "→ %s\n" "$*"; }

# --- tiny-sed wrapper (macOS/BSD & GNU) ---
sedi() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi
}

ensure_dir(){ mkdir -p "$1"; }

# ---------- API: /api/jobs (index) ----------
say "API: /api/jobs (index)…"
ensure_dir "$ROOT/app/api/jobs"
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
      try{
        const j = JSON.parse(await fs.readFile(path.join(JOBS_DIR, f),'utf8'))
        items.push(j)
      }catch{}
    }
    return NextResponse.json({ total: items.length, items })
  }catch(e:any){
    return NextResponse.json({ ok:false, error:String(e) }, { status:500 })
  }
}
TS

# ---------- API: /api/audit/products/[sku] ----------
say "API: /api/audit/products/[sku]…"
ensure_dir "$ROOT/app/api/audit/products/[sku]"
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
    const lines = txt.trim().split(/\r?\n/).map(l=>JSON.parse(l))
    return NextResponse.json({ total: lines.length, items: lines })
  }catch{
    return NextResponse.json({ total: 0, items: [] })
  }
}
TS

# ---------- API: /api/products/completeness (enkel) ----------
say "API: /api/products/completeness…"
ensure_dir "$ROOT/app/api/products/completeness"
cat > "$ROOT/app/api/products/completeness/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { NextRequest } from 'next/server'

const REQUIRED = ['sku','name','price','status','visibility']

async function getJson(url:string){
  const r = await fetch(url, { cache:'no-store' })
  if(!r.ok) throw new Error(`HTTP ${r.status}`)
  return r.json()
}

export async function GET(req:NextRequest){
  const page = Number(req.nextUrl.searchParams.get('page')||1)
  const size = Number(req.nextUrl.searchParams.get('size')||20)
  const q    = req.nextUrl.searchParams.get('q')||''

  // Bruk merged for å inkludere lokale overrides + Magento
  const base = `${process.env.NEXT_PUBLIC_BASE_URL || ''}`
  const host = base || ''
  const url  = `${host}/api/products/merged?page=${page}&size=${size}${q?`&q=${encodeURIComponent(q)}`:''}`

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

# ---------- Components: CompletenessBadge ----------
say "UI: CompletenessBadge komponent…"
ensure_dir "$ROOT/src/components"
cat > "$ROOT/src/components/CompletenessBadge.tsx" <<'TSX'
'use client'
import React from 'react'

export function CompletenessBadge({score, missing}:{score:number; missing:string[]}) {
  const color = score>=90 ? 'bg-green-100 text-green-800' : score>=60 ? 'bg-amber-100 text-amber-800' : 'bg-red-100 text-red-800'
  return (
    <span title={missing.length ? `Missing: ${missing.join(', ')}` : 'Complete'}
          className={`inline-flex items-center gap-2 rounded-full px-2 py-1 text-xs font-medium ${color}`}>
      {score}%{missing.length ? <em className="not-italic opacity-70"> ({missing.length} missing)</em> : null}
    </span>
  )
}
TSX

# ---------- Components: JobsFooter ----------
say "UI: JobsFooter (idempotent, men sørger for eksport)…"
ensure_dir "$ROOT/src/components"
cat > "$ROOT/src/components/JobsFooter.tsx" <<'TSX'
'use client'
import useSWR from 'swr'

const fetcher = (u:string)=>fetch(u).then(r=>r.json())

export function JobsFooter(){
  const { data } = useSWR('/api/jobs', fetcher, { refreshInterval: 5000 })
  const last = data?.items?.[0]
  return (
    <div className="mt-6 border-t pt-3 text-xs text-neutral-600 flex justify-between">
      <div>Jobs: {data?.total ?? 0}</div>
      {last && (
        <div className="opacity-80">Last job: <strong>{last.id}</strong> • {last.type} • products:{last.counts?.products ?? 0} / customers:{last.counts?.customers ?? 0} / orders:{last.counts?.orders ?? 0}</div>
      )}
    </div>
  )
}
TSX

# ---------- Components: SyncNow ----------
say "UI: SyncNow knapp…"
ensure_dir "$ROOT/src/components"
cat > "$ROOT/src/components/SyncNow.tsx" <<'TSX'
'use client'
import React, { useState } from 'react'

export function SyncNow(){
  const [busy,setBusy]=useState(false)
  const [last,setLast]=useState<string|null>(null)
  const run = async ()=>{
    setBusy(true)
    try{
      const r = await fetch('/api/jobs/run-sync', { method:'POST' })
      const j = await r.json()
      setLast(j.id || 'OK')
    }finally{ setBusy(false) }
  }
  return (
    <button onClick={run} disabled={busy}
      className="ml-3 inline-flex items-center rounded-md border px-3 py-1 text-sm shadow-sm hover:bg-neutral-50 disabled:opacity-50">
      {busy ? 'Syncing…' : 'Sync now'} {last ? <span className="ml-2 text-xs opacity-70">{last}</span> : null}
    </button>
  )
}
TSX

# ---------- Pages: /admin/jobs ----------
say "Page: /admin/jobs…"
ensure_dir "$ROOT/app/admin/jobs"
cat > "$ROOT/app/admin/jobs/page.tsx" <<'TSX'
import React from 'react'

async function getJobs(){
  const r = await fetch(`${process.env.NEXT_PUBLIC_BASE_URL || ''}/api/jobs`, { cache:'no-store' })
  return r.json()
}

export default async function JobsPage(){
  const j = await getJobs()
  return (
    <div>
      <h1 className="text-xl font-semibold mb-4">Jobs</h1>
      <div className="rounded-lg border divide-y">
        {(j.items||[]).map((it:any, i:number)=>(
          <div key={it.id || i} className="p-3 text-sm">
            <div className="font-medium">{it.id} — {it.type}</div>
            <div className="opacity-70">started: {it.started} • finished: {it.finished}</div>
            <div className="mt-1">counts: products {it.counts?.products ?? 0}, customers {it.counts?.customers ?? 0}, orders {it.counts?.orders ?? 0}</div>
          </div>
        ))}
      </div>
    </div>
  )
}
TSX

# ---------- Pages: /admin/audit ----------
say "Page: /admin/audit…"
ensure_dir "$ROOT/app/admin/audit"
cat > "$ROOT/app/admin/audit/page.tsx" <<'TSX'
'use client'
import React, { useState } from 'react'

export default function AuditPage(){
  const [sku, setSku] = useState('TEST')
  const [rows, setRows] = useState<any[]>([])
  const [err, setErr] = useState<string|null>(null)

  const load = async ()=>{
    setErr(null)
    try{
      const r = await fetch(`/api/audit/products/${encodeURIComponent(sku)}`)
      const j = await r.json()
      setRows(j.items || [])
    }catch(e:any){ setErr(String(e)) }
  }

  return (
    <div>
      <h1 className="text-xl font-semibold mb-4">Audit</h1>
      <div className="flex gap-2 mb-3">
        <input value={sku} onChange={e=>setSku(e.target.value)} placeholder="SKU" className="border rounded px-2 py-1 text-sm" />
        <button onClick={load} className="border rounded px-3 py-1 text-sm hover:bg-neutral-50">Load</button>
      </div>
      {err && <div className="text-red-600 text-sm mb-2">{err}</div>}
      <div className="rounded border divide-y text-sm">
        {rows.length===0 && <div className="p-3 opacity-70">No audit entries</div>}
        {rows.map((r,i)=>(
          <div key={i} className="p-3">
            <div className="text-xs opacity-70">{r.ts}</div>
            <pre className="overflow-auto text-xs bg-neutral-50 p-2 rounded mt-1">{JSON.stringify(r.after ?? r, null, 2)}</pre>
          </div>
        ))}
      </div>
    </div>
  )
}
TSX

# ---------- Patch admin layout to include SyncNow (idempotent) ----------
LAYOUT="$ROOT/app/admin/layout.tsx"
if [ -f "$LAYOUT" ]; then
  say "Patcher app/admin/layout.tsx (SyncNow + JobsFooter)…"
  grep -q "from '@/src/components/SyncNow'" "$LAYOUT" || \
    sedi "1s|^|import { SyncNow } from '@/src/components/SyncNow'\n|" "$LAYOUT"
  # Sørg for JobsFooter import også (no-op hvis finnes)
  grep -q "from '@/src/components/JobsFooter'" "$LAYOUT" || \
    sedi "1s|^|import { JobsFooter } from '@/src/components/JobsFooter'\n|" "$LAYOUT"
  # Sett inn <SyncNow /> etter <JobsFooter /> i main
  grep -q "<SyncNow" "$LAYOUT" || \
    sedi "s|<JobsFooter />|<JobsFooter /><SyncNow />|" "$LAYOUT" || true
fi

# ---------- Patch products admin table: add CompletenessBadge ----------
PROD_PAGE="$ROOT/app/admin/products/page.tsx"
if [ -f "$PROD_PAGE" ]; then
  say "Patcher products page (CompletenessBadge)…"
  grep -q "from '@/src/components/CompletenessBadge'" "$PROD_PAGE" || \
    sedi "1s|^|import { CompletenessBadge } from '@/src/components/CompletenessBadge'\n|" "$PROD_PAGE"

  # Legg til en ekstra kolonne for completeness (naivt, men idempotent)
  grep -q "CompletenessBadge" "$PROD_PAGE" || cat >> "$PROD_PAGE" <<'ADD'

/** --- Auto-added completeness fetch (very lightweight) --- */
async function _fetchCompleteness() {
  const r = await fetch(`${process.env.NEXT_PUBLIC_BASE_URL || ''}/api/products/completeness?page=1&size=50`, { cache:'no-store' })
  return r.json()
}
ADD
fi

say "Ferdig. Restart dev: npm run dev"