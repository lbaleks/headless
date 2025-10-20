'use client';
import { useEffect, useMemo, useState } from 'react'
import AdminPage from '@/components/AdminPage'
import { totalAvailable, belowROP } from '@/lib/inventory'

type Warehouse = { code:string; onHand:number; reserved:number; reorderPoint?:number; leadTimeDays?:number; moq?:number }
type Product = { id:string; sku:string; name:string; brand?:string; warehouses?:Warehouse[]; stock?:number; supplier?:string; status?:string }

export default function InventoryPage(){
  const [rows,setRows]=useState<Product[]>([])
  const [q,setQ]=useState('')

  useEffect(()=>{ (async()=>{
    const j=await fetch('/api/products?page=1&size=9999',{cache:'no-store'}).then(r=>r.json())
    setRows(j.products||[])
  })() },[])

  const list = useMemo(()=>{
    const t=q.trim().toLowerCase()
    let data = (rows||[]).map(p=>({...p, total: totalAvailable(p) }))
    if(t) data = data.filter(p=> (p.sku+' '+p.name+' '+(p.brand||'')).toLowerCase().includes(t))
    return data.sort((a,b)=>a.name.localeCompare(b.name))
  },[rows,q])

  const critical = list.filter(p=>belowROP(p))

  return (
    <AdminPage title="Inventory" actions={<input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search…" className="border rounded-lg px-2 py-1.5" />}>
      <div className="p-6 grid lg:grid-cols-3 gap-6">
        <section className="lg:col-span-2 rounded-xl border overflow-hidden">
          <table className="min-w-full text-sm">
            <thead className="bg-gray-50"><tr>
              <th className="p-2 text-left">SKU</th>
              <th className="p-2 text-left">Name</th>
              <th className="p-2 text-left">Brand</th>
              <th className="p-2 text-right">Total</th>
              <th className="p-2 text-left">Warehouses</th>
            </tr></thead>
            <tbody>
              {list.map(p=>(
                <tr key={p.id} className={"odd:bg-white even:bg-neutral-50 "+(belowROP(p)?"bg-red-50":"")}>
                  <td className="p-2 border-t font-mono">{p.sku}</td>
                  <td className="p-2 border-t"><a className="underline" href={'/admin/products/'+p.id}>{p.name}</a></td>
                  <td className="p-2 border-t">{p.brand||'—'}</td>
                  <td className="p-2 border-t text-right">{p.total}</td>
                  <td className="p-2 border-t">
                    <div className="flex gap-2 flex-wrap">
                      {(p.warehouses||[]).map((w,i)=>(
                        <span key={i} className="inline-flex items-center gap-1 rounded border px-2 py-0.5 text-xs">
                          {w.code}: {Number(w.onHand||0)-Number(w.reserved||0)}
                          {w.reorderPoint>0 && <span className={(Number(w.onHand||0)-Number(w.reserved||0))<w.reorderPoint?'text-red-600':'text-neutral-400'}> / ROP {w.reorderPoint}</span>}
                        </span>
                      ))}
                      {(p.warehouses||[]).length===0 && <span className="text-xs text-neutral-500">—</span>}
                    </div>
                  </td>
                </tr>
              ))}
              {list.length===0 && <tr><td colSpan={5} className="p-6 text-center text-neutral-500">No products.</td></tr>}
            </tbody>
          </table>
        </section>

        <aside className="space-y-4">
          <div className="rounded-xl border p-4">
            <div className="text-sm text-neutral-500 mb-2">Reorder alerts</div>
            <ul className="text-sm space-y-2">
              {critical.map(p=>(
                <li key={p.id}><a href={'/admin/products/'+p.id} className="underline">{p.sku}</a> · {p.name}</li>
              ))}
              {critical.length===0 && <li className="text-neutral-500">All good ��</li>}
            </ul>
          </div>
        </aside>
      </div>
    </AdminPage>
  )
}
