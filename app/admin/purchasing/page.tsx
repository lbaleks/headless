'use client';
import { useEffect, useMemo, useState } from 'react'
import AdminPage from '@/components/AdminPage'
import { suggestions } from '@/lib/inventory'

type Warehouse = { code:string; onHand:number; reserved:number; reorderPoint?:number; leadTimeDays?:number; moq?:number }
type Product = { id:string; sku:string; name:string; supplier?:string; supplierSku?:string; warehouses?:Warehouse[] }

export default function PurchasingPage(){
  const [rows,setRows]=useState<Product[]>([])
  const [filter,setFilter]=useState('')

  useEffect(()=>{ (async()=>{
    const j=await fetch('/api/products?page=1&size=9999',{cache:'no-store'}).then(r=>r.json())
    setRows(j.products||[])
  })() },[])

  const groups = useMemo(()=>{
    const sugg = suggestions(rows)
    if(!filter) return sugg
    const f = filter.toLowerCase()
    return sugg.map(g=>({ ...g, lines: g.lines.filter(l=>(l.sku+' '+l.name+' '+(g.supplier||'')).toLowerCase().includes(f)) }))
               .filter(g=>g.lines.length>0)
  },[rows,filter])

  const exportJSON=()=>{
    const data = { generatedAt: new Date().toISOString(), groups }
    const blob = new Blob([JSON.stringify(data,null,2)], { type:'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a'); a.href=url; a.download='po-suggestions.json'; a.click(); URL.revokeObjectURL(url)
  }

  const actions=(<>
    <input value={filter} onChange={e=>setFilter(e.target.value)} placeholder="Filter…" className="border rounded-lg px-2 py-1.5"/>
    <button className="border rounded-lg px-3 py-1.5 ml-2" onClick={exportJSON}>Export JSON</button>
  </>)

  return (
    <AdminPage title="Purchasing" actions={actions}>
      <div className="p-6 space-y-6">
        {groups.map(g=>(
          <div key={g.supplier} className="rounded-xl border overflow-hidden">
            <div className="px-3 py-2 bg-gray-50 border-b text-sm font-medium">Supplier: {g.supplier}</div>
            <table className="min-w-full text-sm">
              <thead className="bg-gray-50"><tr>
                <th className="p-2 text-left">SKU</th><th className="p-2 text-left">Name</th><th className="p-2 text-left">Supplier SKU</th>
                <th className="p-2 text-left">Warehouse</th><th className="p-2 text-right">Qty</th>
              </tr></thead>
              <tbody>
                {g.lines.map((l,i)=>(
                  <tr key={i} className="odd:bg-white even:bg-neutral-50">
                    <td className="p-2 border-t font-mono">{l.sku}</td>
                    <td className="p-2 border-t">{l.name}</td>
                    <td className="p-2 border-t font-mono">{l.supplierSku||'—'}</td>
                    <td className="p-2 border-t">{l.warehouse}</td>
                    <td className="p-2 border-t text-right">{l.qty}</td>
                  </tr>
                ))}
                {g.lines.length===0 && <tr><td colSpan={5} className="p-3 text-center text-neutral-500">No lines</td></tr>}
              </tbody>
            </table>
          </div>
        ))}
        {groups.length===0 && <div className="text-neutral-500">No suggestions right now.</div>}
      </div>
    </AdminPage>
  )
}
