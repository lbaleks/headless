'use client';
import React from 'react'
type Credit={ limit?:number; riskScore?:number; terms?:string; notes?:string }
export default function CreditPanel({value,onChange}:{value:Credit;onChange:(v:Credit)=>void}){
  const upd=(k:string,v:any)=>onChange({...(value||{}),[k]:v})
  return (
    <div className="grid md:grid-cols-2 gap-3">
      <div><div className="text-xs text-neutral-500 mb-1">Credit limit (NOK)</div>
        <input type="number" className="lb-input w-full" value={value?.limit??''} onChange={e=>upd('limit', Number(e.target.value))} />
      </div>
      <div><div className="text-xs text-neutral-500 mb-1">Risk score (0–100)</div>
        <input type="number" className="lb-input w-full" value={value?.riskScore??''} onChange={e=>upd('riskScore', Number(e.target.value))} />
      </div>
      <div className="md:col-span-2"><div className="text-xs text-neutral-500 mb-1">Payment terms</div>
        <input className="lb-input w-full" value={value?.terms||''} onChange={e=>upd('terms', e.target.value)} />
      </div>
      <div className="md:col-span-2"><div className="text-xs text-neutral-500 mb-1">Credit notes</div>
        <textarea className="lb-input w-full h-28" value={value?.notes||''} onChange={e=>upd('notes', e.target.value)} />
      </div>
    </div>
  )
}
