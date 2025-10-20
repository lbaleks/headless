'use client';
import React,{useEffect,useState} from 'react'
import AdminPage from '@/components/AdminPage'
export default function PriceLists(){
  const [rows,setRows]=useState<any[]>([])
  useEffect(()=>{(async()=>{const j=await fetch('/api/pricing/pricelists').then(r=>r.json());setRows(j.priceLists||[])})()},[])
  return (<AdminPage title="Price Lists">
    <div className="p-4">
      <table className="min-w-full text-sm"><thead><tr><th className="p-2 text-left">Name</th><th className="p-2">Segment</th><th className="p-2 text-right">Multiplier</th></tr></thead>
      <tbody>{rows.map((p:any)=>(<tr key={p.id} className="odd:bg-white even:bg-gray-50">
        <td className="p-2 border-t">{p.name}</td>
        <td className="p-2 border-t">{p.segment}</td>
        <td className="p-2 border-t text-right">{p.multiplier}</td>
      </tr>))}</tbody></table>
    </div>
  </AdminPage>)
}
