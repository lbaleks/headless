'use client';
import * as React from 'react'
type OptValue={label:string; priceDelta?:number}
type Option={id:string; name:string; type:'select'|'bool'; values?:OptValue[]; required?:boolean}
export default function OptionsEditor({options,onChange}:{options:Option[];onChange:(v:Option[])=>void}){
  const addOption=()=>{const name=prompt('Option name (e.g. Kverning)'); if(!name) return; onChange([...(options||[]), {id:String(Date.now()), name, type:'bool', values:[{label:'Ja',priceDelta:0},{label:'Nei',priceDelta:0}]}])}
  const setName=(id:string,val:string)=> onChange(options.map(o=>o.id===id?{...o,name:val}:o))
  const setType=(id:string,val:'select'|'bool')=> onChange(options.map(o=>o.id===id?{...o,type:val, values:o.values||[]}:o))
  const addValue=(id:string)=> onChange(options.map(o=>o.id===id?{...o,values:[...(o.values||[]),{label:'New',priceDelta:0}]}:o))
  const setValue=(oid:string,idx:number,patch:Partial<OptValue>)=> onChange(options.map(o=>o.id===oid?{...o,values:(o.values||[]).map((v,i)=>i===idx?{...v,...patch}:v)}:o))
  const delValue=(oid:string,idx:number)=> onChange(options.map(o=>o.id===oid?{...o,values:(o.values||[]).filter((_,i)=>i!==idx)}:o))
  const delOption=(id:string)=> onChange((options||[]).filter(o=>o.id!==id))
  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <div className="text-sm text-neutral-500">Configurable options</div>
        <button className="border rounded px-3 py-1.5" onClick={addOption}>Add option</button>
      </div>
      {(options||[]).map(o=>(
        <div key={o.id} className="rounded-lg border bg-white p-3 space-y-2">
          <div className="flex gap-2">
            <input className="lb-input flex-1" value={o.name} onChange={e=>setName(o.id,e.target.value)} placeholder="Option name"/>
            <select className="lb-input" value={o.type} onChange={e=>setType(o.id,e.target.value as any)}>
              <option value="bool">Yes/No</option>
              <option value="select">Select</option>
            </select>
            <button className="border rounded px-2" onClick={()=>delOption(o.id)}>Delete</button>
          </div>
          <div className="text-xs text-neutral-500">Values & price delta</div>
          <table className="lb-table w-full text-sm"><thead><tr><th>Label</th><th className="text-right">Price Δ</th><th></th></tr></thead>
            <tbody>
              {(o.values||[]).map((v,ix)=>(
                <tr key={ix}>
                  <td className="p-2 border-t"><input className="lb-input w-full" value={v.label} onChange={e=>setValue(o.id,ix,{label:e.target.value})}/></td>
                  <td className="p-2 border-t text-right"><input className="lb-input w-28 text-right" type="number" step="0.01" value={v.priceDelta??0} onChange={e=>setValue(o.id,ix,{priceDelta:Number(e.target.value)})}/></td>
                  <td className="p-2 border-t text-right"><button className="border rounded px-2" onClick={()=>delValue(o.id,ix)}>✕</button></td>
                </tr>
              ))}
              {(!o.values||!o.values.length)&&<tr><td className="p-2 text-neutral-500" colSpan={99}>No values</td></tr>}
            </tbody>
          </table>
          <div><button className="border rounded px-2 py-1" onClick={()=>addValue(o.id)}>Add value</button></div>
        </div>
      ))}
      {(!options||!options.length)&&<div className="text-xs text-neutral-500">No options yet.</div>}
    </div>
  )
}
