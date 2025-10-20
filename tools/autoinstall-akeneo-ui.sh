#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="$ROOT/app/api"
SRC="$ROOT/src"
UI="$ROOT/app/admin"
VAR="$ROOT/var"

echo "→ Installerer Akeneo UI-integrasjon..."

# Sørg for alle katalogene (merk [] i path – alltid siter!)
mkdir -p "$API/audit/products/[sku]" \
         "$API/jobs/run-sync" \
         "$SRC/components" \
         "$UI/products" \
         "$VAR/audit"

# -------------------------------------------------------------------
# 1) API: Audit leser
# -------------------------------------------------------------------
cat > "$API/audit/products/[sku]/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

export async function GET(_:Request, { params }: { params:{ sku:string } }) {
  const file = path.join(process.cwd(), 'var', 'audit', `products.${params.sku}.jsonl`)
  try {
    const txt = await fs.readFile(file, 'utf8')
    const lines = txt.trim().split('\n').slice(-50).map(l => JSON.parse(l))
    return NextResponse.json({ total: lines.length, items: lines })
  } catch {
    return NextResponse.json({ total: 0, items: [] })
  }
}
TS
echo "  • /api/audit/products/[sku] (GET) klart"

# -------------------------------------------------------------------
# 2) API: run-sync trigger
# -------------------------------------------------------------------
cat > "$API/jobs/run-sync/route.ts" <<'TS'
import { NextResponse } from 'next/server'

export async function POST() {
  const base = process.env.BASE_URL || 'http://localhost:3000'
  const start = new Date().toISOString()
  const [p, c, o] = await Promise.all([
    fetch(`${base}/api/products/sync`, { method:'POST' }).then(r=>r.json()).catch(()=>({saved:0})),
    fetch(`${base}/api/customers/sync`, { method:'POST' }).then(r=>r.json()).catch(()=>({saved:0})),
    fetch(`${base}/api/orders/sync`, { method:'POST' }).then(r=>r.json()).catch(()=>({saved:0}))
  ])
  const job = {
    id: 'JOB-'+Date.now(),
    ts: new Date().toISOString(),
    type: 'sync-all',
    started: start,
    finished: new Date().toISOString(),
    counts: { products:p.saved||0, customers:c.saved||0, orders:o.saved||0 }
  }
  await fetch(`${base}/api/jobs`, { method:'POST', headers:{'content-type':'application/json'}, body: JSON.stringify(job) })
  return NextResponse.json(job)
}
TS
echo "  • /api/jobs/run-sync (POST) klart"

# -------------------------------------------------------------------
# 3) UI-komponenter
# -------------------------------------------------------------------
cat > "$SRC/components/CompletenessBadge.tsx" <<'TSX'
'use client'
import React from 'react'
type Props = { score:number }
export const CompletenessBadge = ({ score }:Props)=>{
  let color='bg-gray-200 text-gray-700'
  if(score>=90) color='bg-green-100 text-green-800'
  else if(score>=50) color='bg-yellow-100 text-yellow-800'
  else color='bg-red-100 text-red-800'
  return <span className={`text-xs px-2 py-1 rounded-full ${color}`}>{score}%</span>
}
TSX
echo "  • CompletenessBadge.tsx"

cat > "$SRC/components/BulkEditDialog.tsx" <<'TSX'
'use client'
import React, { useState } from 'react'

export function BulkEditDialog(){
  const [skus,setSkus]=useState('')
  const [price,setPrice]=useState('')
  const [status,setStatus]=useState('')
  const [log,setLog]=useState('')
  const submit=async()=>{
    const items=skus.split(/\s+/).filter(Boolean).map(sku=>({sku,changes:{}} as any))
    for(const i of items){
      if(price) (i.changes as any).price=Number(price)
      if(status) (i.changes as any).status=Number(status)
    }
    const r=await fetch('/api/products/bulk',{method:'PATCH',headers:{'content-type':'application/json'},body:JSON.stringify({items})})
    const j=await r.json()
    setLog(JSON.stringify(j,null,2))
  }
  return <div className="p-4 border rounded-md bg-white shadow-sm">
    <h2 className="font-semibold mb-2">Bulk edit produkter</h2>
    <textarea value={skus} onChange={e=>setSkus(e.target.value)} placeholder="SKU1 SKU2 SKU3" className="w-full border p-2 mb-2 h-20"/>
    <div className="flex gap-2 mb-2">
      <input value={price} onChange={e=>setPrice(e.target.value)} placeholder="Ny pris" className="border p-1 w-24"/>
      <input value={status} onChange={e=>setStatus(e.target.value)} placeholder="Status" className="border p-1 w-24"/>
    </div>
    <button onClick={submit} className="bg-blue-600 text-white px-3 py-1 rounded">Lagre</button>
    {log && <pre className="mt-3 bg-gray-50 p-2 text-xs">{log}</pre>}
  </div>
}
TSX
echo "  • BulkEditDialog.tsx"

cat > "$SRC/components/JobsFooter.tsx" <<'TSX'
'use client'
import React,{useEffect,useState} from 'react'
export function JobsFooter(){
  const [job,setJob]=useState<any>(null)
  const load=async()=>{const j=await fetch('/api/jobs').then(r=>r.json());setJob(j.items?.[0])}
  const run=async()=>{await fetch('/api/jobs/run-sync',{method:'POST'});await load()}
  useEffect(()=>{load()},[])
  return <div className="p-2 text-xs bg-neutral-50 flex justify-between border-t">
    <div>{job ? <>🔄 Sist sync: {new Date(job.ts).toLocaleTimeString()} ({job.counts?.products||0} produkter)</> : 'Ingen jobber'}</div>
    <button onClick={run} className="text-blue-600 hover:underline">Kjør sync</button>
  </div>
}
TSX
echo "  • JobsFooter.tsx"

echo "✓ Ferdig. Restart dev-server: npm run dev"
echo "Test:"
echo "  curl -s http://localhost:3000/api/audit/products/TEST | jq '.total'"
echo "  curl -s -X POST http://localhost:3000/api/jobs/run-sync | jq '.id,.counts'"