'use client';
import React from 'react'
import AdminPage from '@/components/AdminPage'
type P={id:string;sku:string;name:string;price?:number;cost?:number;stock?:number;status?:string}
export default function GridEdit(){
  const [rows,setRows]=React.useState<P[]>([])
  const [sel,setSel]=React.useState<Record<string,boolean>>({})
  const [q,setQ]=React.useState('')
  React.useEffect(()=>{ (async()=>{ const j=await fetch('/api/products').then(r=>r.json()).catch(()=>({products:[]})); setRows(j.products||[]) })() },[])
  const upd=(i:number,patch:Partial<P>)=>setRows(r=>r.map((x,ix)=>ix===i?{...x,...patch}:x))
  const filtered=rows.filter(r=>[r.sku,r.name].join(' ').toLowerCase().includes(q.toLowerCase()))
  const bulkSet=(patch:Partial<P>)=>setRows(r=>r.map(x=> sel[x.id]? {...x,...patch}:x))
  return (
    <AdminPage title="Products · Grid Edit" actions={<div className="flex gap-2">
      <input className="lb-input" placeholder="Search…" value={q} onChange={e=>setQ(e.target.value)} />
      <button className="border rounded px-3 py-1.5" onClick={()=>{ const v=prompt('Set status for selected (active/draft/archived):','active'); if(v) bulkSet({status:v}) }}>Bulk: Status</button>
      <button className="border rounded px-3 py-1.5" onClick={()=>{ const v=Number(prompt('Set price for selected:','0')||0); bulkSet({price:v}) }}>Bulk: Price</button>
      <button className="border rounded px-3 py-1.5" onClick={()=>{ const v=Number(prompt('Set cost for selected:','0')||0); bulkSet({cost:v}) }}>Bulk: Cost</button>
    </div>}>
      <div className="lb-card p-0 overflow-auto">
        <table className="lb-table min-w-[900px]">
          <thead><tr><th><input type="checkbox" onChange={e=>{ const on=e.target.checked; const n:Record<string,boolean>={}; filtered.forEach(x=>n[x.id]=on); setSel(n) }}/></th><th>SKU</th><th>Name</th><th className="text-right">Price</th><th className="text-right">Cost</th><th className="text-right">Stock</th><th>Status</th></tr></thead>
          <tbody>
            {filtered.map((p,i)=>(
              <tr key={p.id} className="odd:bg-white even:bg-gray-50">
                <td><input type="checkbox" checked={!!sel[p.id]} onChange={e=>setSel(s=>({...s,[p.id]:e.target.checked}))}/></td>
                <td className="font-mono">{p.sku}</td>
                <td><input className="lb-input w-full" value={p.name||''} onChange={e=>upd(i,{name:e.target.value})}/></td>
                <td className="text-right"><input type="number" step="0.01" className="lb-input w-28 text-right" value={p.price??0} onChange={e=>upd(i,{price:Number(e.target.value||0)})}/></td>
                <td className="text-right"><input type="number" step="0.01" className="lb-input w-28 text-right" value={p.cost??0} onChange={e=>upd(i,{cost:Number(e.target.value||0)})}/></td>
                <td className="text-right"><input type="number" className="lb-input w-24 text-right" value={p.stock??0} onChange={e=>upd(i,{stock:Number(e.target.value||0)})}/></td>
                <td>
                  <select className="lb-input" value={p.status||'draft'} onChange={e=>upd(i,{status:e.target.value})}>
                    <option value="active">active</option><option value="draft">draft</option><option value="archived">archived</option>
                  </select>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </AdminPage>
  )
}
