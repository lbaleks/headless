"use client";
import { useEffect, useState } from 'react'
import { Card } from '@/components/ui/Card'

type Activity={ id:string; customerId:string; type:'note'|'call'|'email'; subject:string; body?:string; at:string; author?:string }
type Task={ id:string; customerId:string; title:string; due?:string; status:'open'|'in_progress'|'done'; assignee?:string }

export default function CRMPanel({ customerId }:{ customerId:string }){
  const [activities,setActivities]=useState<Activity[]>([])
  const [tasks,setTasks]=useState<Task[]>([])
  const [title,setTitle]=useState(''); const [due,setDue]=useState(''); const [assignee,setAssignee]=useState('')

  const load=async()=>{
    const a=await fetch('/api/crm?type=activities&customerId='+customerId,{cache:'no-store'}).then(r=>r.json())
    const t=await fetch('/api/crm?type=tasks&customerId='+customerId,{cache:'no-store'}).then(r=>r.json())
    setActivities(a.activities||[]); setTasks(t.tasks||[])
  }
  useEffect(()=>{ load() },[customerId])

  const addTask=async()=>{
    if(!title.trim()) return
    await fetch('/api/crm',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({type:'task',data:{customerId,title,due,assignee}})})
    setTitle(''); setDue(''); setAssignee(''); load()
  }
  const toggleTask=async(t:Task)=>{
    await fetch('/api/crm',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({type:'task',data:{...t,status: t.status==='done'?'open':'done'}})})
    load()
  }
  const delTask=async(id:string)=>{
    await fetch('/api/crm?type=task&id='+id,{method:'DELETE'}).catch(()=>{})
    load()
  }

  return (
    <div className="space-y-4">
      <Card title="Tasks" actions={<button className="lb-btn" onClick={addTask}>Add</button>}>
        <div className="grid md:grid-cols-3 gap-2 mb-3">
          <input className="lb-input" placeholder="Title" value={title} onChange={e=>setTitle(e.target.value)}/>
          <input className="lb-input" placeholder="Due (YYYY-MM-DD)" value={due} onChange={e=>setDue(e.target.value)}/>
          <input className="lb-input" placeholder="Assignee" value={assignee} onChange={e=>setAssignee(e.target.value)}/>
        </div>
        <ul className="space-y-2">
          {tasks.map(t=>(
            <li key={t.id} className="flex items-center justify-between border rounded-lg px-3 py-2">
              <div className="text-sm">
                <label className="inline-flex items-center gap-2">
                  <input type="checkbox" checked={t.status==='done'} onChange={()=>toggleTask(t)}/>
                  <span className={t.status==='done'?'line-through text-neutral-400':''}>{t.title}</span>
                </label>
                <div className="text-xs lb-muted">{t.due||'—'} · {t.assignee||'—'}</div>
              </div>
              <button className="text-xs text-red-600" onClick={()=>delTask(t.id)}>Delete</button>
            </li>
          ))}
          {tasks.length===0 && <li className="text-sm lb-muted">No tasks</li>}
        </ul>
      </Card>

      <Card title="Activity">
        <ul className="space-y-3">
          {activities.map(a=>(
            <li key={a.id} className="text-sm">
              <div className="font-medium">{a.subject}</div>
              <div className="lb-muted text-xs">{a.type} · {new Date(a.at).toLocaleString()}</div>
              {a.body && <div className="mt-1">{a.body}</div>}
            </li>
          ))}
          {activities.length===0 && <li className="text-sm lb-muted">No activity</li>}
        </ul>
      </Card>
    </div>
  )
}
