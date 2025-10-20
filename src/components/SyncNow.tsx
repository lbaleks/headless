"use client";
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
