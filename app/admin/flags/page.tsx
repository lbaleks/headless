'use client';
import { useEffect, useMemo, useState } from 'react'
import AdminPage from '@/components/AdminPage'

type Flag={ key:string; name:string; enabled:boolean; desc?:string }
export default function FlagsPage(){
  const [flags,setFlags]=useState<Flag[]>([])
  const [q,setQ]=useState('')
  const [busy,setBusy]=useState(false)
  const load=async()=>{ const r=await fetch('/api/flags',{cache:'no-store'}); const j=await r.json(); setFlags(j.flags||[]) }
  useEffect(()=>{ load() },[])
  const filtered = useMemo(()=> flags.filter(f => (f.key+f.name+ (f.desc||'')).toLowerCase().includes(q.toLowerCase())), [flags,q])

  const toggle=async(f:Flag)=>{ setBusy(true); await fetch('/api/flags',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({...f,enabled:!f.enabled})}); await load(); setBusy(false) }
  const add=async()=>{
    const key = prompt('Flag key (unique):')?.trim(); if(!key) return
    const name = prompt('Name:')?.trim() || key
    const desc = prompt('Description (optional):')?.trim() || ''
    const enabled = confirm('Enabled by default?')
    setBusy(true); const r=await fetch('/api/flags',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({key,name,enabled,desc})}); if(!r.ok) alert(await r.text()); await load(); setBusy(false)
  }
  const del=async(f:Flag)=>{ if(!confirm('Delete '+f.key+'?')) return; setBusy(true); await fetch('/api/flags?key='+f.key,{method:'DELETE'}); await load(); setBusy(false) }

  return (
    <AdminPage title="Feature Flags">
      <div className="flex items-center justify-between mb-3">
        <input className="border rounded p-2 w-64" placeholder="Search flags…" value={q} onChange={e=>setQ(e.target.value)} />
        <button className="px-3 py-1.5 border rounded bg-black text-white" onClick={add} disabled={busy}>New flag</button>
      </div>
      <div className="rounded-2xl border overflow-hidden">
        <table className="min-w-full text-sm">
          <thead className="bg-gray-50">
            <tr><th className="p-3 text-left">Key</th><th className="p-3 text-left">Name</th><th className="p-3 text-left">Description</th><th className="p-3 text-center">Enabled</th><th className="p-3 text-right">Actions</th></tr>
          </thead>
          <tbody>
            {filtered.map(f=>(
              <tr key={f.key} className="odd:bg-white even:bg-gray-50">
                <td className="p-3 border-t font-mono">{f.key}</td>
                <td className="p-3 border-t">{f.name}</td>
                <td className="p-3 border-t">{f.desc||'—'}</td>
                <td className="p-3 border-t text-center">{f.enabled?'✅':'❌'}</td>
                <td className="p-3 border-t text-right space-x-2">
                  <button className="px-2 py-1 border rounded" onClick={()=>toggle(f)} disabled={busy}>{f.enabled?'Disable':'Enable'}</button>
                  <button className="px-2 py-1 border rounded text-red-600" onClick={()=>del(f)} disabled={busy}>Delete</button>
                </td>
              </tr>
            ))}
            {filtered.length===0 && <tr><td colSpan={5} className="p-6 text-center text-gray-500">No flags match.</td></tr>}
          </tbody>
        </table>
      </div>
    </AdminPage>
  )
}
