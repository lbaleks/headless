'use client';
import React from 'react'
export default function KeyValue({items}:{items:Record<string,React.ReactNode>|[string,React.ReactNode][]}){
  const entries = Array.isArray(items)? items : Object.entries(items)
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
      {entries.map(([k,v],i)=>(
        <div key={i} className="flex items-start justify-between gap-3 border rounded-lg px-3 py-2">
          <div className="text-neutral-500">{k}</div>
          <div className="font-medium text-right break-words">{v??'—'}</div>
        </div>
      ))}
    </div>
  )
}
