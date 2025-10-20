'use client';
import React from 'react'
import { Card } from './Card'
type Tier={ name:string; qtyFrom:number; price:number; currency?:string }
export default function PriceTiers({tiers,onChange}:{tiers:Tier[]; onChange?:(t:Tier[])=>void}){
  const [rows,setRows]=React.useState<Tier[]>(tiers||[])
  React.useEffect(()=>{ onChange?.(rows) },[rows])
  const add=()=>setRows(r=>[...r,{name:'Tier '+(r.length+1),qtyFrom:1,price:0}])
  const del=(i:number)=>setRows(r=>r.filter((_,ix)=>ix!==i))
  const upd=(i:number,patch:Partial<Tier>)=>setRows(r=>r.map((x,ix)=>ix===i?{...x,...patch}:x))
  return (
    <Card title="Price tiers" actions={<button className="text-xs border rounded px-2 py-1" onClick={add}>Add tier</button>}>
      <table className="min-w-full text-sm">
        <thead><tr><th className="p-2 text-left">Name</th><th className="p-2 text-right">From qty</th><th className="p-2 text-right">Price</th><th className="p-2"></th></tr></thead>
        <tbody>
          {rows.map((t,i)=>(
            <tr key={i} className="odd:bg-white even:bg-gray-50">
              <td className="p-2 border-t"><input className="lb-input w-full" value={t.name} onChange={e=>upd(i,{name:e.target.value})}/></td>
              <td className="p-2 border-t text-right"><input type="number" className="lb-input w-28 text-right" value={t.qtyFrom} onChange={e=>upd(i,{qtyFrom:Math.max(1,Number(e.target.value||1))})}/></td>
              <td className="p-2 border-t text-right"><input type="number" step="0.01" className="lb-input w-32 text-right" value={t.price} onChange={e=>upd(i,{price:Number(e.target.value||0)})}/></td>
              <td className="p-2 border-t text-right"><button className="text-xs text-red-600" onClick={()=>del(i)}>Remove</button></td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  )
}
