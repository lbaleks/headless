/* eslint-disable jsx-a11y/no-static-element-interactions */
'use client';
import { useEffect, useMemo, useState } from 'react'
import AdminPage from '@/components/AdminPage'

type Item={ sku:string; name:string; qty:number; price:number }
type History={ at:string; by?:string; status:string; note?:string }
type Order={ id:string; total:number; status:string; items:Item[]; history?:History[]; currency?:string }

const COLUMNS=['created','paid','picked','packed','shipped','completed'] as const

export default function Kanban(){
  const [rows,setRows]=useState<Order[]>([])
  const [q,setQ]=useState('')
  const load=async()=>{ const j=await fetch('/api/orders?page=1&size=9999',{cache:'no-store'}).then(r=>r.json()); setRows(j.orders||[]) }
  useEffect(()=>{ load() },[])
  const data=useMemo(()=>{
    const f=q.toLowerCase()
    const list=rows.filter(o=>(o.id+' '+o.status+' '+o.items.map(i=>i.sku).join(' ')).toLowerCase().includes(f))
    const map:Record<string,Order[]>={}; COLUMNS.forEach(c=>map[c]=[])
    list.forEach(o=>{ (map[o.status]||(map[o.status]=[])).push(o) })
    return map
  },[rows,q])

  const onDrop=async(e:React.DragEvent, col:string)=>{
    const id=e.dataTransfer.getData('text/plain')
    if(!id) return
    await fetch('/api/orders',{method:'PATCH',headers:{'content-type':'application/json'},body:JSON.stringify({id, status:col, note:'Moved on Kanban'})})
    load()
  }

  return (
    <AdminPage title="Orders · Kanban" actions={<input className="lb-input" placeholder="Search orders…" value={q} onChange={e=>setQ(e.target.value)}/>}>
      <div className="p-6 grid grid-cols-1 md:grid-cols-3 xl:grid-cols-6 gap-4">
        {COLUMNS.map(col=>(
          <div key={col} className="bg-neutral-50 border rounded-xl p-3 min-h-[60vh]" onDragOver={e=>e.preventDefault()} onDrop={e=>onDrop(e,col)}>
            <div className="font-semibold mb-2 capitalize">{col}</div>
            <div className="space-y-2">
              {(data[col]||[]).map(o=>(
                <a key={o.id} href={'/admin/orders/'+o.id} draggable onDragStart={e=>e.dataTransfer.setData('text/plain',o.id)} className="block border rounded-lg bg-white px-3 py-2">
                  <div className="flex items-center justify-between text-sm">
                    <div className="font-medium">#{o.id}</div>
                    <div>{(o.total||0).toFixed(2)} {o.currency||'NOK'}</div>
                  </div>
                  <div className="text-xs text-neutral-500">{o.items.map(i=>i.sku).join(', ')}</div>
                </a>
              ))}
              {(data[col]||[]).length===0 && <div className="text-xs text-neutral-400">Empty</div>}
            </div>
          </div>
        ))}
      </div>
    </AdminPage>
  )
}
