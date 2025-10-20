'use client';
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
