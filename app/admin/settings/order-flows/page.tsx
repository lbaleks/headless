'use client';
import React from 'react'
import AdminPage from '@/components/AdminPage'
export default function OrderFlows(){
  const [rows,setRows]=React.useState([{id:'new',label:'New'},{id:'processing',label:'Processing'},{id:'picked',label:'Picked'},{id:'dispatched',label:'Dispatched'},{id:'captured',label:'Captured'},{id:'complete',label:'Complete'}])
  const add=()=>setRows(r=>[...r,{id:'custom-'+(r.length+1),label:'Custom'}])
  return (
    <AdminPage title="Settings · Order Flows" actions={<button className="border rounded px-3 py-1.5" onClick={add}>Add step</button>}>
      <div className="lb-card p-0 overflow-hidden">
        <table className="lb-table">
          <thead><tr><th>ID</th><th>Label</th></tr></thead>
          <tbody>
            {rows.map((s,i)=>(
              <tr key={i} className="odd:bg-white even:bg-gray-50">
                <td className="font-mono">{s.id}</td>
                <td><input className="lb-input w-full" value={s.label} onChange={e=>setRows(r=>r.map((x,ix)=>ix===i?{...x,label:e.target.value}:x))}/></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="text-sm lb-muted mt-3">(Lagring kommer når vi spikrer config-modell)</div>
    </AdminPage>
  )
}
