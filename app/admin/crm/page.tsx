'use client';
import { useEffect, useMemo, useState } from 'react'
import AdminPage from '@/components/AdminPage'
import { Card } from '@/components/ui/Card'
type Task={ id:string; customerId:string; title:string; due?:string; status:'open'|'in_progress'|'done'; assignee?:string }
export default function CRMHome(){
  const [tasks,setTasks]=useState<Task[]>([]); const [q,setQ]=useState('')
  useEffect(()=>{ fetch('/api/crm?type=tasks',{cache:'no-store'}).then(r=>r.json()).then(j=>setTasks(j.tasks||[])) },[])
  const list=useMemo(()=>tasks.filter(t=>(t.title+' '+(t.assignee||'')+' '+(t.customerId||'')).toLowerCase().includes(q.toLowerCase())),[tasks,q])
  return (
    <AdminPage title="CRM" actions={<input className="lb-input" placeholder="Search tasks…" value={q} onChange={e=>setQ(e.target.value)}/>}>
      <div className="p-6 grid md:grid-cols-2 xl:grid-cols-3 gap-4">
        {list.map(t=>(<Card key={t.id} title={t.title} actions={<a className="lb-btn" href={'/admin/customers/'+t.customerId}>Open customer</a>}>
          <div className="text-sm">Status: <b>{t.status}</b></div>
          <div className="text-sm">Assignee: {t.assignee||'—'}</div>
          <div className="text-xs lb-muted">Due: {t.due||'—'}</div>
        </Card>))}
        {list.length===0 && <div className="lb-muted">No tasks</div>}
      </div>
    </AdminPage>
  )
}
