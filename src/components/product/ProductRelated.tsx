'use client';
import React from 'react'
type Rel={id:string; name?:string; sku?:string}
export default function ProductRelated({items,onRemove}:{items:Rel[]; onRemove:(id:string)=>void}){
  const list = Array.isArray(items)?items:[]
  if(!list.length) return <div className="text-sm text-neutral-500">No related products yet.</div>
  return (
    <ul className="divide-y border rounded-xl bg-white">
      {list.map((r,i)=>(
        <li key={r.id||i} className="flex items-center justify-between p-3">
          <div>
            <div className="font-medium text-sm">{r.name||r.id}</div>
            <div className="text-xs text-neutral-500">{r.sku}</div>
          </div>
          <button className="text-xs text-red-600" onClick={()=>onRemove(r.id)}>Remove</button>
        </li>
      ))}
    </ul>
  )
}
