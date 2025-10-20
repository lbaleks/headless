'use client';
import * as React from 'react'
type Item = { id?:string; tone?:'info'|'success'|'warn'|'danger'|'neutral'; text:string; ts:number }
export default function ProductActivity({ items }:{ items:Item[] }){
  const list = items||[]
  return (
    <div className="space-y-3">
      {list.map((i,ix)=>(
        <div key={`${i.id||'act'}-${ix}`} className="relative pl-4">
          <div className={"absolute left-0 top-2 h-2 w-2 rounded-full "+({info:'bg-blue-600',success:'bg-green-600',warn:'bg-amber-500',danger:'bg-red-600',neutral:'bg-neutral-300'}[i.tone||'neutral'])}/>
          <div className="text-sm">{i.text}</div>
          <div className="text-xs text-neutral-500">{new Date(i.ts).toLocaleString()}</div>
        </div>
      ))}
    </div>
  )
}
