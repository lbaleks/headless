#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Forutsetter at disse finnes fra før (du har dem)
# - /api/products/[sku] (GET)
# - /api/products/update-attributes (PATCH)
# - /api/audit/products/[sku] (GET, jsonl-til-JSON)
# - /api/akeneo/attributes (GET) – definerer familier/attributter

# --- Komponent: AttributeEditor (client)
mkdir -p src/components
if [ ! -f src/components/AttributeEditor.tsx ]; then
log "Skriver src/components/AttributeEditor.tsx"
cat > src/components/AttributeEditor.tsx <<'TSX'
'use client'
import * as React from 'react'
import useSWR from 'swr'

const fetcher=(u:string)=>fetch(u).then(r=>r.json())
type KV = Record<string, any>

export function AttributeEditor({ sku, onSaved }:{ sku:string, onSaved?:()=>void }) {
  const { data:meta } = useSWR('/api/akeneo/attributes', fetcher)
  const { data:prod } = useSWR(`/api/products/${encodeURIComponent(sku)}`, fetcher)
  const [attrsText, setAttrsText] = React.useState<string>('')
  const [busy, setBusy] = React.useState(false)
  const attributes:KV = prod?.attributes || {}
  const fam = (prod?.family ?? 'default') as string
  const famReq:string[] = meta?.families?.[fam]?.required ?? meta?.families?.default?.required ?? []

  React.useEffect(()=>{
    setAttrsText(JSON.stringify(attributes, null, 2))
  }, [prod?.sku])

  async function save() {
    try{
      setBusy(true)
      const parsed = attrsText.trim() ? JSON.parse(attrsText) : {}
      const r = await fetch('/api/products/update-attributes', {
        method:'PATCH', headers:{'content-type':'application/json'},
        body: JSON.stringify({ sku, attributes: parsed })
      })
      if(!r.ok) throw new Error(`Save failed ${r.status}`)
      onSaved?.()
      // revalidate:
      ;(await import('swr')).mutate(`/api/products/${encodeURIComponent(sku)}`)
      ;(await import('swr')).mutate(`/api/products/completeness?sku=${encodeURIComponent(sku)}`)
      ;(await import('swr')).mutate(`/api/audit/products/${encodeURIComponent(sku)}`)
    }catch(e:any){
      alert(e?.message || String(e))
    }finally{
      setBusy(false)
    }
  }

  return (
    <div className="grid gap-3">
      <div className="text-sm text-neutral-600">
        Family: <span className="font-medium">{fam}</span> — Required: {famReq.join(', ')}
      </div>
      <label className="text-sm font-medium">Attributes (JSON)</label>
      <textarea
        className="w-full h-48 font-mono text-sm border rounded p-2"
        value={attrsText} onChange={e=>setAttrsText(e.target.value)}
        placeholder='{"ibu": 60, "hops": "Mosaic"}'
      />
      <button onClick={save} disabled={busy}
        className="self-start rounded px-3 py-1 border hover:bg-neutral-50 disabled:opacity-50">
        {busy? 'Saving…':'Save attributes'}
      </button>
    </div>
  )
}
TSX
else
  log "AttributeEditor.tsx fantes (ok)"
fi

# --- Side: /admin/products/[sku]
mkdir -p app/admin/products/[sku]
log "Skriver app/admin/products/[sku]/page.tsx"
cat > app/admin/products/[sku]/page.tsx <<'TSX'
'use client'
import * as React from 'react'
import useSWR from 'swr'
import Link from 'next/link'
import { AttributeEditor } from '@/src/components/AttributeEditor'

const fetcher=(u:string)=>fetch(u).then(r=>r.json())

export default function ProductDetail({ params }:{ params:{ sku:string } }) {
  const sku = decodeURIComponent(params.sku)
  const { data:prod } = useSWR(`/api/products/${encodeURIComponent(sku)}`, fetcher)
  const { data:comp } = useSWR(`/api/products/completeness?sku=${encodeURIComponent(sku)}`, fetcher)
  const { data:audit }= useSWR(`/api/audit/products/${encodeURIComponent(sku)}`, fetcher)

  const item = comp?.items?.[0]
  const score = item?.completeness?.score ?? 0
  const missing = item?.completeness?.missing ?? []
  const fam = item?.family ?? (prod?.family ?? 'default')

  return (
    <main className="mx-auto max-w-6xl px-4 py-6 grid gap-6">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-sm"><Link className="underline" href="/admin/products">← Back to list</Link></div>
          <h1 className="text-2xl font-semibold mt-1">Product <span className="font-mono">{sku}</span></h1>
          <div className="text-neutral-600 mt-1">
            Family: <span className="font-medium">{fam}</span> · Completeness: <span className="font-medium">{score}%</span>
            {missing.length>0 && <span className="ml-2 text-amber-600">Missing: {missing.join(', ')}</span>}
          </div>
        </div>
        <div className="text-sm">
          <div><b>Type:</b> {prod?.type ?? '—'}</div>
          <div><b>Price:</b> {prod?.price ?? '—'}</div>
          <div><b>Source:</b> {prod?.source ?? '—'}</div>
        </div>
      </div>

      <section className="grid md:grid-cols-2 gap-6">
        <div className="p-4 border rounded">
          <h2 className="font-semibold mb-3">Attributes</h2>
          <AttributeEditor sku={sku} />
        </div>

        <div className="p-4 border rounded">
          <h2 className="font-semibold mb-3">Audit</h2>
          {!audit?.items?.length && <div className="text-sm text-neutral-500">No audit entries.</div>}
          <ul className="space-y-3 max-h-[420px] overflow-auto">
            {audit?.items?.map((e:any, i:number)=>(
              <li key={i} className="text-sm">
                <div className="text-neutral-500">{new Date(e.ts).toLocaleString()}</div>
                <pre className="bg-neutral-50 border rounded p-2 overflow-auto">
{JSON.stringify({before:e.before, after:e.after}, null, 2)}
                </pre>
              </li>
            ))}
          </ul>
        </div>
      </section>
    </main>
  )
}
TSX

# --- Patch: sikre at liste-siden lenker til detalj (idempotent)
if [ -f app/admin/products/page.tsx ]; then
  node <<'JS'
const fs=require('fs'); const p='app/admin/products/page.tsx'
let s=fs.readFileSync(p,'utf8'), b=s
if(!/href=\{`\/admin\/products\/\$\{p\.sku\}`\}/.test(s)){
  s=s.replace(/<td className="font-mono">([^<]*)<\/td>/,
    `<td className="font-mono"><a className="underline" href={\`/admin/products/\${p.sku}\`}>{p.sku}</a></td>`)
}
if(s!==b){ fs.writeFileSync(p,s); console.log('• Lenke til detalj injisert i admin/products') } else { console.log('• Lenke fantes (ok)') }
JS
fi

# --- Smoke
log "Smoke API: product + completeness + audit (TEST)"
curl -s "http://localhost:3000/api/products/TEST" | jq '.sku,.source' >/dev/null || true
curl -s "http://localhost:3000/api/products/completeness?sku=TEST" | jq '.items[0].completeness.score' >/dev/null || true
curl -s "http://localhost:3000/api/audit/products/TEST" | jq '.total' >/dev/null || true
log "Ferdig ✅  Åpne: /admin/products/TEST"
