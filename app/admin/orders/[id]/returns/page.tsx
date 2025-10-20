
'use client';
import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'next/navigation'
import AdminPage from '@/components/AdminPage'

type Item = { sku:string; name?:string; qty:number; price?:number }
type Order = { id:string; status:string; currency?:string; items:Item[]; returns?:any[] }

export default function OrderReturns(){
  const { id } = useParams() as { id:string }
  const [o,setO]=useState<Order|null|undefined>(undefined)
  const [sel,setSel]=useState<Record<string,number>>({})
  const [busy,setBusy]=useState(false)

  const load=async()=>{
    setO(undefined)
    const j = await fetch('/api/orders/'+id).then(r=>r.ok?r.json():null).catch(()=>null)
    setO(j??null)
  }
  useEffect(()=>{ load() },[id])

  const selectable = useMemo(()=> (o?.items||[]).map(i=>({sku:i.sku, name:i.name||i.sku, max:i.qty})),[o])
  const canSubmit = Object.values(sel).some(v=>Number(v)>0)

  const submit = async()=>{
    setBusy(true)
    try{
      const items = Object.entries(sel).filter(([,_q])=>Number(_q)>0).map(([sku,qty])=>({sku,qty:Number(qty)}))
      const res = await fetch('/api/orders/'+id+'/returns', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({items})})
      if(!res.ok) throw new Error('HTTP '+res.status)
      ;(window as any).lbToast?.('Return created')
      setSel({})
      await load()
    }catch(e:any){
      console.error(e); (window as any).lbToast?.('Create return failed')
    }finally{ setBusy(false) }
  }

  if(o===undefined) return <AdminPage title={'Order '+id+' · Returns'}><div className="p-6">Loading…</div></AdminPage>
  if(o===null) return <AdminPage title={'Order '+id+' · Returns'}><div className="p-6 text-red-600">Order not found.</div></AdminPage>

  return (
    <AdminPage title={'Order '+id+' · Returns'}>
      <div className="p-6 grid lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-4">
          <div className="rounded-xl border bg-white p-4">
            <div className="text-sm text-neutral-500 mb-2">Select items to return</div>
            <table className="min-w-full text-sm">
              <thead><tr><th className="p-2 text-left">SKU</th><th className="p-2 text-left">Name</th><th className="p-2 text-right">Qty (max)</th><th className="p-2 text-right">Return</th></tr></thead>
              <tbody>
                {selectable.map(i=>(
                  <tr key={i.sku} className="odd:bg-white even:bg-gray-50">
                    <td className="p-2 border-t font-mono">{i.sku}</td>
                    <td className="p-2 border-t">{i.name}</td>
                    <td className="p-2 border-t text-right">{i.max}</td>
                    <td className="p-2 border-t text-right">
                      <input type="number" className="lb-input w-24 text-right"
                        value={sel[i.sku]||0}
                        min={0} max={i.max}
                        onChange={e=>setSel(s=>({...s,[i.sku]:Math.max(0, Math.min(i.max, Number(e.target.value||0)))}))}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <button className="lb-btn lb-btn--pri mt-3 disabled:opacity-50" disabled={!canSubmit||busy} onClick={submit}>Create return</button>
          </div>

          <div className="rounded-xl border bg-white p-4">
            <div className="text-sm text-neutral-500 mb-2">Existing returns</div>
            <ul className="text-sm space-y-2">
              {(o.returns||[]).map((r:any)=>(
                <li key={r.id} className="rounded border p-2">
                  <div>Return #{r.id} · {r.status} · {new Date(r.createdAt).toLocaleString()}</div>
                  <div className="text-neutral-500">{r.items.map((i:any)=>i.sku+'×'+i.qty).join(', ')}</div>
                </li>
              ))}
              {(!o.returns||!o.returns.length) && <li className="text-neutral-500">No returns yet.</li>}
            </ul>
          </div>
        </div>
      </div>
    </AdminPage>
  )
}
