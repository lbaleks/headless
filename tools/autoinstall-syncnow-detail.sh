#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

mkdir -p src/components

# 1) Mini-komponent
if [ ! -f src/components/SyncNowMini.tsx ]; then
log "Skriver src/components/SyncNowMini.tsx"
cat > src/components/SyncNowMini.tsx <<'TSX'
'use client'
import * as React from 'react'

export function SyncNowMini() {
  const [busy,setBusy]=React.useState(false)
  const [msg,setMsg]=React.useState<string|null>(null)

  async function run() {
    try{
      setBusy(true); setMsg(null)
      const r = await fetch('/api/jobs/run-sync', { method:'POST' })
      const j = await r.json()
      if(!r.ok) throw new Error(j?.error || `Run-sync feilet ${r.status}`)
      setMsg(`OK: ${j.id}`)
      // småløft: revalidate noen APIer
      ;(await import('swr')).mutate('/api/jobs')
      ;(await import('swr')).mutate('/api/jobs/latest')
    }catch(e:any){
      setMsg(e?.message || String(e))
    }finally{
      setBusy(false)
    }
  }

  return (
    <div className="inline-flex items-center gap-2">
      <button onClick={run} disabled={busy}
        className="rounded px-3 py-1 border hover:bg-neutral-50 disabled:opacity-50">
        {busy? 'Syncing…':'Sync now'}
      </button>
      {msg && <span className="text-xs text-neutral-600">{msg}</span>}
    </div>
  )
}
TSX
else
  log "SyncNowMini.tsx fantes (ok)"
fi

# 2) Patch detaljside til å vise knappen i header
if [ -f app/admin/products/[sku]/page.tsx ]; then
node <<'JS'
const fs=require('fs'); const p='app/admin/products/[sku]/page.tsx'
let s=fs.readFileSync(p,'utf8'), b=s
if(!/from '@\/src\/components\/SyncNowMini'/.test(s)){
  s = s.replace(/(^|\n)import .*FamilyPicker.*\n?/,
                m => m + "import { SyncNowMini } from '@/src/components/SyncNowMini'\n")
}
if(!/SyncNowMini \/>/.test(s)){
  // legg på høyresiden der vi viser Type/Price/Source
  s = s.replace(/(<div className="text-sm">\s*<div><b>Type:)/,
    `<div className="mb-2 text-right"><SyncNowMini /></div>\n          $1`)
}
if(s!==b){ fs.writeFileSync(p,s); console.log('• SyncNowMini injisert på detaljsiden') } else { console.log('• SyncNowMini fantes (ok)') }
JS
fi

# 3) Røyk
log "Smoke: POST /api/jobs/run-sync"
curl -fsS -X POST http://localhost:3000/api/jobs/run-sync | jq '.id' >/dev/null || { echo "✗ feilet"; exit 1; }

log "Ferdig ✅  Åpne: /admin/products/TEST (Sync now-knapp)"
