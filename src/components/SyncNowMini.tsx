"use client";
import { useState, useEffect } from "react";

export default function SyncNowMini() {
  const [busy,setBusy]=useState(false)
  const [msg,setMsg]=useState<string|null>(null)

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
