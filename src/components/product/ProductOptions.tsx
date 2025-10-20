'use client';
import * as React from 'react'
import { Field } from '@/components/ui/Field'

type OptionRow = { key:string; label:string; enabled:boolean; priceDelta?:number }
type Props = {
  value?: OptionRow[]
  onChange: (rows: OptionRow[]) => void
}
const DEFAULTS: OptionRow[] = [
  { key:'milling', label:'Kverning', enabled:false, priceDelta:0 },
]

export default function ProductOptions({value,onChange}:Props){
  const rows = React.useMemo<OptionRow[]>(()=> {
    const map = new Map((value||[]).map(r=>[r.key,r]))
    return DEFAULTS.map(d=> map.get(d.key) ?? d)
  },[value])

  const setRow = (ix:number, patch: Partial<OptionRow>)=>{
    const next = rows.map((r,i)=> i===ix ? {...r,...patch} : r)
    onChange(next)
  }

  return (
    <div className="space-y-3">
      {rows.map((r,ix)=>(
        <div key={r.key} className="grid grid-cols-1 md:grid-cols-3 gap-3 items-end border rounded-lg p-3">
          <Field label={r.label}>
            <div className="flex items-center gap-2">
              <input type="checkbox" checked={!!r.enabled} onChange={e=>setRow(ix,{enabled:e.target.checked})}/>
              <span className="text-sm text-neutral-700">Aktiver</span>
            </div>
          </Field>
          <Field label="Pris-tillegg">
            <input type="number" step="0.01" className="lb-input"
              value={Number(r.priceDelta||0)}
              onChange={e=>setRow(ix,{priceDelta:Number(e.target.value)||0})}/>
          </Field>
          <div className="text-xs text-neutral-500 md:text-right">Lag tilleggsopsjoner (f.eks. slip, montering) ved behov – strukturen er generisk.</div>
        </div>
      ))}
    </div>
  )
}
