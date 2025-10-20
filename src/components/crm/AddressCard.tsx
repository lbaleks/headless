'use client';
import React from 'react'
type Addr={ name?:string; line1?:string; line2?:string; postal?:string; city?:string; country?:string }
export default function AddressCard({label,value,onChange}:{label:string;value:Addr;onChange:(v:Addr)=>void}){
  const upd=(k:string,v:any)=>onChange({...(value||{}),[k]:v})
  return (
    <div className="rounded-lg border p-3">
      <div className="text-xs text-neutral-500 mb-2">{label}</div>
      <div className="grid md:grid-cols-2 gap-2">
        <input className="lb-input" placeholder="Name" value={value?.name||''} onChange={e=>upd('name',e.target.value)}/>
        <input className="lb-input" placeholder="Line 1" value={value?.line1||''} onChange={e=>upd('line1',e.target.value)}/>
        <input className="lb-input" placeholder="Line 2" value={value?.line2||''} onChange={e=>upd('line2',e.target.value)}/>
        <input className="lb-input" placeholder="Postal" value={value?.postal||''} onChange={e=>upd('postal',e.target.value)}/>
        <input className="lb-input" placeholder="City" value={value?.city||''} onChange={e=>upd('city',e.target.value)}/>
        <input className="lb-input" placeholder="Country" value={value?.country||''} onChange={e=>upd('country',e.target.value)}/>
      </div>
    </div>
  )
}
