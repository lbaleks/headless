"use client";
import Image from "next/image";import * as React from 'react'
import { Field } from '@/components/ui/Field'

type MediaItem = { url:string; alt?:string }
export default function ProductMedia({
  value, onChange
}:{ value?: MediaItem[]; onChange:(rows:MediaItem[])=>void }){
  const rows = value||[]

  const onFile = async (f:File|null)=>{
    if(!f) return
    const fd = new FormData()
    fd.set('file', f)
    const res = await fetch('/api/upload',{ method:'POST', body:fd })
    const j = await res.json().catch(()=>null)
    if(j?.ok && j.url){
      onChange([...(rows||[]), {url:j.url, alt:f.name}])
    }else{
      (window as any).lbToast?.('Upload failed')
    }
  }

  const set = (ix:number, patch:Partial<MediaItem>)=>{
    onChange(rows.map((r,i)=> i===ix ? {...r,...patch} : r))
  }
  const del = (ix:number)=> onChange(rows.filter((_,i)=>i!==ix))

  return (
    <div className="space-y-3">
      <Field label="Legg til bilde">
        <input type="file" accept="image/*" onChange={e=>onFile(e.target.files?.[0]||null)}/>
      </Field>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {rows.map((m,ix)=>(
          <div key={`${m.url}-${ix}`} className="border rounded-lg p-2">
            <Image src={m.url} alt={m.alt||""} width={600} height={400} className="w-full h-32 object-cover rounded" />
            <input className="lb-input mt-2" placeholder="Alt text" value={m.alt||''} onChange={e=>set(ix,{alt:e.target.value})}/>
            <div className="mt-2 text-right">
              <button className="lb-btn" onClick={()=>del(ix)}>Delete</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
