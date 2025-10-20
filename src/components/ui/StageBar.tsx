'use client';
import React from 'react'
type Stage={ id:string; label:string; done?:boolean; current?:boolean }
export default function StageBar({stages}:{stages:Stage[]}) {
  return (
    <div className="flex items-center gap-2">
      {stages.map((s,i)=>(
        <div key={s.id} className="flex items-center gap-2">
          <div className={"h-2 w-2 rounded-full "+(s.done?'bg-green-600':s.current?'bg-blue-600':'bg-neutral-300')} />
          <div className={"text-xs "+(s.current?'font-medium text-blue-700':'text-neutral-600')}>{s.label}</div>
          {i<stages.length-1 && <div className="w-6 h-px bg-neutral-200 mx-1" />}
        </div>
      ))}
    </div>
  )
}
