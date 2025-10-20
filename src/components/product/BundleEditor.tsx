'use client';
import React from 'react'
import { Card } from '@/components/ui/Card'
import type { ProductBundleItem } from '@/types/product'

export default function BundleEditor({value,onChange}:{value:ProductBundleItem[];onChange?:(v:ProductBundleItem[])=>void}){
  const [rows,setRows]=React.useState<ProductBundleItem[]>(value||[])
  React.useEffect(()=>{ onChange?.(rows) },[rows])
  const add=()=>setRows(r=>[...r,{sku:'',qty:1}])
  const del=(i:number)=>setRows(r=>r.filter((_,ix)=>ix!==i))
  const upd=(i:number,patch:Partial<ProductBundleItem>)=>setRows(r=>r.map((x,ix)=>ix===i?{...x,...patch}:x))
  return (
    <Card title="Bundle / Set items" actions={<button className="text-xs border rounded px-2 py-1" onClick={add}>Add item</button>}>
      <table className="min-w-full text-sm">
        <thead><tr><th className="p-2 text-left">SKU</th><th className="p-2 text-right">Qty</th><th className="p-2"></th></tr></thead>
        <tbody>
          {rows.map((b,i)=>(
            <tr key={i} className="odd:bg-white even:bg-gray-50">
              <td className="p-2 border-t"><input className="lb-input w-full" value={b.sku} onChange={e=>upd(i,{sku:e.target.value})}/></td>
              <td className="p-2 border-t text-right"><input type="number" className="lb-input w-24 text-right" value={b.qty} onChange={e=>upd(i,{qty:Math.max(1,Number(e.target.value||1))})}/></td>
              <td className="p-2 border-t text-right"><button className="text-xs text-red-600" onClick={()=>del(i)}>Remove</button></td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="text-xs text-neutral-500 mt-2">Brukes til bundles/product sets (Salesforce/DW-inspirert).</div>
    </Card>
  )
}