'use client';
import * as React from 'react'

export type Tab = { key:string; label:string }
export default function Tabs({
  tabs, active, onChange
}:{ tabs:Tab[]; active:string; onChange:(key:string)=>void }){
  return (
    <div className="border-b">
      <div role="tablist" className="flex gap-1">
        {tabs.map(t=>(
          <button
            key={t.key}
            role="tab"
            aria-selected={active===t.key}
            onClick={()=>onChange(t.key)}
            className={
              'px-3 py-2 text-sm rounded-t border-b-2 -mb-px '+
              (active===t.key
                ? 'border-blue-600 text-neutral-900'
                : 'border-transparent text-neutral-500 hover:text-neutral-800')
            }>
            {t.label}
          </button>
        ))}
      </div>
    </div>
  )
}
