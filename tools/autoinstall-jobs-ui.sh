#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

fetcher_js='const fetcher=(u)=>fetch(u,{cache:"no-store"}).then(r=>r.json())'

log "Writer SyncNow (client)"
mkdir -p src/components
cat > src/components/SyncNow.tsx <<'TSX'
'use client'
import {useState} from 'react'

export default function SyncNow({className}:{className?:string}){
  const [busy,setBusy]=useState(false)
  const [msg,setMsg]=useState<string|null>(null)

  async function run(){
    try{
      setBusy(true); setMsg(null)
      const r = await fetch('/api/jobs/run-sync',{method:'POST'})
      if(r.status===429){ setMsg('Opptatt – prøv igjen straks.'); return }
      if(!r.ok){ setMsg('Feil fra server.'); return }
      const j = await r.json()
      setMsg(`Startet ${j.id}`)
    }catch(e:any){
      setMsg('Ukjent feil')
    }finally{ setBusy(false) }
  }

  return (
    <div className={className}>
      <button
        onClick={run}
        disabled={busy}
        className="rounded-lg border px-3 py-1 text-sm hover:bg-neutral-50 disabled:opacity-50">
        {busy ? 'Synker…' : 'Sync now'}
      </button>
      {msg && <span className="ml-2 text-sm text-neutral-500">{msg}</span>}
    </div>
  )
}
TSX

log "Writer JobsPanel (client)"
cat > src/components/JobsPanel.tsx <<'TSX'
'use client'
import useSWR from 'swr'
import SyncNow from '@/src/components/SyncNow'
const fetcher=(u:string)=>fetch(u,{cache:'no-store'}).then(r=>r.json())

export default function JobsPanel(){
  const {data, isLoading, mutate} = useSWR('/api/jobs', fetcher, {refreshInterval: 4000})
  const items = data?.items ?? []
  const last = items[0]

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Jobs</h1>
        <SyncNow />
      </div>

      <div className="rounded-xl border p-4 grid sm:grid-cols-3 gap-4">
        <div>
          <div className="text-sm text-neutral-500">Siste job</div>
          <div className="font-mono">{last?.id ?? '–'}</div>
        </div>
        <div>
          <div className="text-sm text-neutral-500">Startet</div>
          <div className="font-mono">{last?.started ?? '–'}</div>
        </div>
        <div>
          <div className="text-sm text-neutral-500">Ferdig</div>
          <div className="font-mono">{last?.finished ?? '–'}</div>
        </div>
      </div>

      <div className="rounded-xl border overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead className="bg-neutral-50">
            <tr>
              <th className="text-left p-2">ID</th>
              <th className="text-left p-2">Type</th>
              <th className="text-left p-2">Start</th>
              <th className="text-left p-2">Slutt</th>
              <th className="text-left p-2">Counts</th>
            </tr>
          </thead>
          <tbody>
            {items.map((j:any,i:number)=>(
              <tr key={j.id ?? i} className="border-t hover:bg-neutral-50">
                <td className="p-2 font-mono">{j.id}</td>
                <td className="p-2">{j.type}</td>
                <td className="p-2 font-mono">{j.started}</td>
                <td className="p-2 font-mono">{j.finished}</td>
                <td className="p-2 font-mono">
                  {j.counts ? JSON.stringify(j.counts) : '–'}
                </td>
              </tr>
            ))}
            {!items.length && !isLoading && (
              <tr><td colSpan={5} className="p-4 text-neutral-500">Ingen jobber funnet.</td></tr>
            )}
            {isLoading && (
              <tr><td colSpan={5} className="p-4 text-neutral-500">Laster…</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
TSX

log "Writer /admin/jobs page"
mkdir -p app/admin/jobs
cat > app/admin/jobs/page.tsx <<'TS'
import JobsPanel from '@/src/components/JobsPanel'
export default function Page(){ return <JobsPanel/> }
TS

log "Legger til lenke i admin/layout.tsx (idempotent)"
node - <<'JS'
const fs=require('fs'); const p='app/admin/layout.tsx'
if(!fs.existsSync(p)) process.exit(0)
let s=fs.readFileSync(p,'utf8'), b=s
if(!/href="\/admin\/jobs"/.test(s)){
  s = s.replace(/(<nav[^>]*>[\s\S]*?<ul[^>]*>)/, `$1\n        <li><a href="/admin/jobs" className="underline">Jobs</a></li>`)
}
if(s!==b){ fs.writeFileSync(p,s); console.log('• Lenke "Jobs" lagt til i admin-layout') } else { console.log('• Lenke fantes (ok)') }
JS

log "Røyk-test API"
curl -s 'http://localhost:3000/api/jobs' >/dev/null && echo "• /api/jobs OK" || echo "• /api/jobs FEIL"

log "Ferdig ✅  Åpne /admin/jobs"
