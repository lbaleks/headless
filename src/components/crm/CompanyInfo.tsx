'use client';
import React from 'react'
type Info={ company?:string; website?:string; vat?:string; size?:string; industry?:string }
export default function CompanyInfo({value,onChange}:{value:Info;onChange:(v:Info)=>void}){
  const u=(k:string,v:any)=>onChange({...(value||{}),[k]:v})
  return (
    <div className="grid md:grid-cols-2 gap-3">
      <input className="lb-input" placeholder="Company" value={value?.company||''} onChange={e=>u('company',e.target.value)}/>
      <input className="lb-input" placeholder="Website" value={value?.website||''} onChange={e=>u('website',e.target.value)}/>
      <input className="lb-input" placeholder="VAT / Org no." value={value?.vat||''} onChange={e=>u('vat',e.target.value)}/>
      <input className="lb-input" placeholder="Company size" value={value?.size||''} onChange={e=>u('size',e.target.value)}/>
      <input className="lb-input md:col-span-2" placeholder="Industry" value={value?.industry||''} onChange={e=>u('industry',e.target.value)}/>
    </div>
  )
}
