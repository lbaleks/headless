'use client';
import React from 'react'
import { Card } from '@/components/ui/Card'
import type { ProductVariant } from '@/types/product'

export default function VariantEditor({value,onChange}:{value:ProductVariant[];onChange?:(v:ProductVariant[])=>void}){
  const [rows,setRows]=React.useState<ProductVariant[]>(value||[])
  React.useEffect(()=>{ onChange?.(rows) },[rows])
  const add=()=>setRows(r=>[...r,{id:String(Date.now()),name:'New variant',multiplier:1}])
  const del=(id:string)=>setRows(r=>r.filter(x=>x.id!==id))
  const upd=(id:string,patch:Partial<ProductVariant>)=>setRows(r=>r.map(x=>x.id===id?{...x,...patch}:x))
  return (
    <Card title="Variants" actions={<button className="text-xs border rounded px-2 py-1" onClick={add}>Add variant</button>}>
      <table className="min-w-full text-sm">
        <thead><tr><th className="p-2 text-left">Name</th><th className="p-2 text-right">Multiplier</th><th className="p-2 text-left">SKU (opt)</th><th className="p-2 text-right">Price adj. (opt)</th><th className="p-2"></th></tr></thead>
        <tbody>
          {rows.map(v=>(
            <tr key={v.id} className="odd:bg-white even:bg-gray-50">
              <td className="p-2 border-t"><input className="lb-input w-full" value={v.name} onChange={e=>upd(v.id,{name:e.target.value})}/></td>
              <td className="p-2 border-t text-right"><input type="number" step="1" className="lb-input w-28 text-right" value={v.multiplier} onChange={e=>upd(v.id,{multiplier:Math.max(1,Number(e.target.value||1))})}/></td>
              <td className="p-2 border-t"><input className="lb-input w-full" value={v.sku||''} onChange={e=>upd(v.id,{sku:e.target.value||undefined})}/></td>
              <td className="p-2 border-t text-right"><input type="number" step="0.01" className="lb-input w-32 text-right" value={v.priceAdj??0} onChange={e=>upd(v.id,{priceAdj:Number(e.target.value||0)})}/></td>
              <td className="p-2 border-t text-right"><button className="text-xs text-red-600" onClick={()=>del(v.id)}>Remove</button></td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="text-xs text-neutral-500 mt-2">Tip: multiplier 250 = “sekk” med 250 enheter. Price adj. brukes som tillegg/avslag pr variant.</div>
    </Card>
  )
}