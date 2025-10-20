'use client';
import * as React from 'react'
export default function TagInput({value,onChange}:{value:string[], onChange:(v:string[])=>void}){
  const [draft,setDraft]=React.useState('')
  const add=()=>{ const v=draft.trim(); if(!v) return; if(value.includes(v)) return; onChange([...value,v]); setDraft('') }
  const del=(t:string)=> onChange(value.filter(x=>x!==t))
  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        <input className="lb-input" placeholder="Add tag…" value={draft} onChange={e=>setDraft(e.target.value)} onKeyDown={e=>{ if(e.key==='Enter'){ e.preventDefault(); add() }}}/>
        <button className="lb-btn" onClick={add}>Add</button>
      </div>
      <div className="flex flex-wrap gap-2">
        {value.map(t=>(
          <span key={t} className="inline-flex items-center gap-2 px-2 py-1 text-xs rounded bg-neutral-100 border border-neutral-200">
            {t}
            <button className="text-neutral-500 hover:text-neutral-800" onClick={()=>del(t)}>×</button>
          </span>
        ))}
      </div>
    </div>
  )
}
