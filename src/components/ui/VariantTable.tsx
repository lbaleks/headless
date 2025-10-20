'use client';
import React from 'react'
import { Card } from './Card'
type Variant={ id?:string; label?:string; sku?:string; multiplier?:number; price?:number }
export default function VariantTable({rows,onChange}:{rows:Variant[]; onChange?:(v:Variant[])=>void}){
  const [list,setList]=React.useState<Variant[]>(rows||[])
  React.useEffect(()=>{ onChange?.(list) },[list])
  const add=()=>setList(x=>[...x,{label:'New variant',multiplier:1}])
  const del=(i:number)=>setList(x=>x.filter((_,ix)=>ix!==i))
  const upd=(i:number,p:Partial<Variant>)=>setList(x=>x.map((r,ix)=>ix===i?{...r,...p}:r))
  return (
    <Card title="Variants" actions={<button className="text-xs border rounded px-2 py-1" onClick={add}>Add</button>}>
      <table className="min-w-full text-sm">
        <thead><tr><th className="p-2 text-left w-[35%]">Label</th><th className="p-2 text-left">SKU</th><th className="p-2 text-right">Multiplier</th><th className="p-2 text-right">Price</th><th className="p-2"></th></tr></thead>
        <tbody>
          {list.length? list.map((v,i)=>(
            <tr key={i} className="odd:bg-white even:bg-gray-50">
              <td className="p-2 border-t"><input className="lb-input w-full" value={v.label||''} onChange={e=>upd(i,{label:e.target.value})}/></td>
              <td className="p-2 border-t"><input className="lb-input w-full" value={v.sku||''} onChange={e=>upd(i,{sku:e.target.value})}/></td>
              <td className="p-2 border-t text-right"><input type="number" className="lb-input w-24 text-right" value={v.multiplier||1} onChange={e=>upd(i,{multiplier:Math.max(1,Number(e.target.value||1))})}/></td>
              <td className="p-2 border-t text-right"><input type="number" step="0.01" className="lb-input w-28 text-right" value={v.price||0} onChange={e=>upd(i,{price:Number(e.target.value||0)})}/></td>
              <td className="p-2 border-t text-right"><button className="text-xs text-red-600" onClick={()=>del(i)}>Remove</button></td>
            </tr>
          )): <tr><td className="p-2 border-t text-neutral-500" colSpan={5}>No variants</td></tr>}
        </tbody>
      </table>
    </Card>
  )
}
