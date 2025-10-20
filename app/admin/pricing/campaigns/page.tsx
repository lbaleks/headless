'use client';
import React,{useEffect,useState} from 'react'
import AdminPage from '@/components/AdminPage'
export default function Campaigns(){
  const [rows,setRows]=useState<any[]>([])
  useEffect(()=>{(async()=>{const j=await fetch('/api/pricing/campaigns').then(r=>r.json());setRows(j.campaigns||[])})()},[])
  return (<AdminPage title="Campaigns">
    <div className="p-4">
      <table className="min-w-full text-sm"><thead><tr><th className="p-2 text-left">Name</th><th className="p-2">Type</th><th className="p-2">Condition</th></tr></thead>
      <tbody>{rows.map((c:any)=>(<tr key={c.id} className="odd:bg-white even:bg-gray-50">
        <td className="p-2 border-t">{c.name}</td>
        <td className="p-2 border-t">{c.action?.type}</td>
        <td className="p-2 border-t">{c.conditions?.skuIn? 'SKU in '+c.conditions.skuIn.join(', ') : '—'}</td>
      </tr>))}</tbody></table>
    </div>
  </AdminPage>)
}
