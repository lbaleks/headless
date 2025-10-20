'use client';
import * as React from 'react'

type Task = { id:string; text:string; done?:boolean }
export default function TaskList({
  value = [],
  onChange
}:{ value?:Task[]; onChange:(next:Task[])=>void }){
  const items = Array.isArray(value) ? value : []
  const toggle = (id:string)=>{
    onChange(items.map(t => t.id===id ? {...t, done:!t.done} : t))
  }
  return (
    <div>
      <div className="text-sm text-neutral-500 mb-2">Tasks</div>
      <ul className="space-y-1">
        {items.map(t=>(
          <li key={t.id} className="flex items-center gap-2">
            <input type="checkbox" checked={!!t.done} onChange={()=>toggle(t.id)} />
            <span className={"text-sm "+(t.done?'line-through text-neutral-400':'')}>{t.text}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}
