'use client';
import { useEffect, useState } from 'react'
import type { PricingRule, RuleType, RuleTarget } from '@/lib/pricing'

export default function RuleEditor({
  value, onChange, onSave, onCancel
}:{ value:PricingRule, onChange:(r:PricingRule)=>void, onSave:()=>void, onCancel:()=>void }){
  const [r,setR]=useState<PricingRule>(value)
  useEffect(()=>{ setR(value) },[value])
  useEffect(()=>{ onChange(r) },[r])

  const set = (patch:Partial<PricingRule>) => setR(prev=>({...prev, ...patch}))
  const types:RuleType[]=['percent_off','fixed_amount','set_price']
  const targets:RuleTarget[]=['all','sku','category','brand','query']

  return (
    <div className="w-[420px] max-w-[90vw] bg-white h-full overflow-auto border-l">
      <div className="p-4 border-b">
        <div className="text-lg font-semibold">{r.id ? 'Edit rule' : 'New rule'}</div>
        <div className="text-xs text-neutral-500">Pricing rule configuration</div>
      </div>
      <div className="p-4 space-y-3">
        <label className="text-sm block">Name
          <input className="mt-1 w-full border rounded p-2" value={r.name||''} onChange={e=>set({name:e.target.value})}/>
        </label>
        <div className="grid grid-cols-2 gap-2">
          <label className="text-sm">Type
            <select className="mt-1 w-full border rounded p-2" value={r.type||'percent_off'} onChange={e=>set({type:e.target.value as RuleType})}>
              {types.map(t=><option key={t} value={t}>{t}</option>)}
            </select>
          </label>
          <label className="text-sm">Value
            <input type="number" step="0.01" className="mt-1 w-full border rounded p-2 text-right" value={r.value||0} onChange={e=>set({value:Number(e.target.value)})}/>
          </label>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <label className="text-sm">Target
            <select className="mt-1 w-full border rounded p-2" value={r.target||'all'} onChange={e=>set({target:e.target.value as RuleTarget})}>
              {targets.map(t=><option key={t} value={t}>{t}</option>)}
            </select>
          </label>
          <label className="text-sm">Match (optional)
            <input className="mt-1 w-full border rounded p-2" placeholder="sku fragment / category / brand / query" value={r.match||''} onChange={e=>set({match:e.target.value})}/>
          </label>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <label className="text-sm">Priority
            <input type="number" className="mt-1 w-full border rounded p-2 text-right" value={r.priority??0} onChange={e=>set({priority:Number(e.target.value)})}/>
          </label>
          <label className="text-sm">Active
            <select className="mt-1 w-full border rounded p-2" value={r.active? '1':'0'} onChange={e=>set({active:e.target.value==='1'})}>
              <option value="1">Yes</option><option value="0">No</option>
            </select>
          </label>
        </div>
      </div>
      <div className="p-4 border-t flex gap-2 justify-end">
        <button className="border rounded px-3 py-1.5" onClick={onCancel}>Cancel</button>
        <button className="border rounded px-3 py-1.5 bg-black text-white" onClick={onSave}>Save</button>
      </div>
    </div>
  )
}
