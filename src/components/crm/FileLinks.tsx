'use client';
import React from 'react'
type F={ id:string; name:string; url:string }
export default function FileLinks({value,onChange}:{value:F[];onChange:(v:F[])=>void}){
  const [name,setName]=React.useState(''); const [url,setUrl]=React.useState('')
  const add=()=>{ const n=name.trim(), u=url.trim(); if(!n||!u) return; onChange([...(value||[]), {id:crypto.randomUUID(), name:n, url:u}]); setName(''); setUrl('') }
  const del=(id:string)=>onChange(value.filter(x=>x.id!==id))
  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        <input className="lb-input flex-1" placeholder="File name" value={name} onChange={e=>setName(e.target.value)}/>
        <input className="lb-input flex-[2]" placeholder="https://…" value={url} onChange={e=>setUrl(e.target.value)}/>
        <button className="btn" onClick={add}>Add</button>
      </div>
      <ul className="space-y-1">
        {(value||[]).map(f=>(
          <li key={f.id} className="flex items-center gap-2">
            <a className="link" href={f.url} target="_blank" rel="noreferrer">{f.name}</a>
            <button className="ml-auto text-neutral-500 hover:text-red-600" onClick={()=>del(f.id)}>Delete</button>
          </li>
        ))}
      </ul>
    </div>
  )
}
