'use client';
import * as React from 'react'
export default function Timeline({items}:{items:{id:string; text:string; ts:string; tone?:'info'|'success'|'warn'|'danger'|'neutral'}[]}){
  return (
    <div className="space-y-3">
      {items.map(i=>(
        <div key={i.id} className="relative pl-4">
          <div className={
            "absolute left-0 top-1.5 h-2 w-2 rounded-full "+
            ({info:'bg-blue-600',success:'bg-green-600',warn:'bg-amber-500',danger:'bg-red-600',neutral:'bg-neutral-300'}[i.tone||'neutral'])
          }/>
          <div className="text-sm">{i.text}</div>
          <div className="text-xs text-neutral-500">{new Date(i.ts).toLocaleString()}</div>
        </div>
      ))}
    </div>
  )
}
