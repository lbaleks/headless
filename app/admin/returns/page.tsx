'use client';
import * as React from 'react'

export default function ReturnsPage(){
  const [rows,setRows]=React.useState<any[]>([])
  React.useEffect(()=>{(async()=>{
    const j = await fetch('/api/returns',{cache:'no-store'}).then(r=>r.json()).catch(()=>({returns:[]}))
    setRows(j.returns||[])
  })()},[])
  return (
    <div>
      <div className="text-xl font-semibold mb-3">Returns</div>
      <div className="admin-panel p-3">
        <table className="w-full text-sm lb-table">
          <thead><tr><th>ID</th><th>Order</th><th>Status</th><th>Created</th></tr></thead>
          <tbody>
            {rows.length===0 && <tr><td colSpan={99} className="p-3 text-neutral-500">No returns yet</td></tr>}
            {rows.map((r)=>(
              <tr key={r.id}>
                <td className="p-2">{r.id}</td>
                <td className="p-2">{r.orderId}</td>
                <td className="p-2 capitalize">{r.status||'open'}</td>
                <td className="p-2">{r.created_at? new Date(r.created_at).toLocaleString():'-'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
