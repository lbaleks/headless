"use client";
;
import { normMult } from '@/utils/inventory';
import React,{useEffect,useMemo,useState} from 'react';
import { useParams } from 'next/navigation';
import AdminPage from '@/components/AdminPage';
import RecordHeader from '@/components/ui/RecordHeader';
import { Card } from '@/components/ui/Card'


type Item={ sku:string; name:string; qty:number; price:number }
type Order={ id:string; status?:string; currency?:string; total:number; items:Item[]; customer?:{name?:string}; shippingAddress?:any }

// Defensive money helper
function lbMoney(x:any){ return Number(x ?? 0) }

export default function OrderFulfillment(){
  const { id } = useParams<{id:string}>() as {id:string}
  const [o,setO]=useState<Order|null|undefined>(undefined)
  const [picked,setPicked]=useState<Record<string,number>>({})
  const [packed,setPacked]=useState(false)
  const [tracking,setTracking]=useState('')

  useEffect(()=>{
    let alive=true
    async function load(){
      try{
        let res=await fetch('/api/orders/'+encodeURIComponent(id))
        if(!res.ok){ res=await fetch('/api/orders?id='+encodeURIComponent(id)) }
        if(!res.ok){ if(alive) setO(null); return }
        const j=await res.json().catch(()=>null)
        const ord=j?.order||j||null
        if(alive) setO(ord)
      }catch{ if(alive) setO(null) }
    }
    load(); return ()=>{ alive=false }
  },[id])

  const allPicked = useMemo(()=> o? o.items.every(i=>Number(picked[i.sku]||0)>=i.qty) : false,[o,picked])
  const markShipped = ()=>{
    (window as any).lbToast?.('Order marked shipped') // placeholder
  }

  if(o===undefined) return <AdminPage title={'Order '+id}><div className="p-6">Loading…</div></AdminPage>
  if(o===null) return <AdminPage title={'Order '+id}><div className="p-6 text-red-600">Order not found.</div></AdminPage>

  return (
    <AdminPage title={'Order '+id+' · Fulfillment'}>
      <RecordHeader
        title={'Order '+id}
        subtitle={o.customer?.name? ('Customer: '+o.customer.name):undefined}
        status={{ text:(o.status||'processing') as any, tone: o.status==='complete'?'success':(o.status==='canceled'?'danger':'info') }}
        kpis={[
          {label:'Items', value: String(o.items?.length||0)},
          {label:'Picked', value: o.items? String(o.items.reduce((a,i)=>a+(picked[i.sku]||0),0)) : '0'},
          {label:'Ready', value: allPicked&&packed? 'Yes':'No'},
          {label:'Tracking', value: tracking||'—'},
        ]}
      />
      <div className="p-6 grid lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-4">
          <Card title="Pick">
            <table className="lb-table text-sm w-full">
              <thead><tr><th className="p-2 text-left">SKU</th><th className="p-2 text-left">Name</th><th className="p-2 text-right">Qty</th><th className="p-2 text-right">Picked</th></tr></thead>
              <tbody>
                {o.items.map(i=>(
                  <tr key={i.sku} className="odd:bg-white even:bg-gray-50">
                    <td className="p-2 border-t font-mono">{i.sku}</td>
                    <td className="p-2 border-t">{i.name}</td>
                    <td className="p-2 border-t text-right">{i.qty}</td>
                    <td className="p-2 border-t text-right">
                      <input type="number" className="lb-input w-24 text-right" value={picked[i.sku]||0}
                        onChange={e=>setPicked({...picked,[i.sku]:Math.max(0,Number(e.target.value||0))})}/>
                    </td>
                  </tr>
                ))}
              </tbody>{(!Array.isArray($1)||!$1.length)&&<tbody><tr><td className="p-3 text-neutral-500" colSpan={99}>No rows</td></tr></tbody>}
            </table>
          </Card>

          <Card title="Pack">
            <label className="inline-flex items-center gap-2 text-sm">
              <input type="checkbox" checked={packed} onChange={e=>setPacked(e.target.checked)}/>
              All items packed and labeled
            </label>
          </Card>
        </div>

        <div className="space-y-4">
          <Card title="Ship">
            <div className="text-sm">Tracking number</div>
            <input className="lb-input w-full mt-1" value={tracking} onChange={e=>setTracking(e.target.value)} placeholder="e.g. BRING123..." />
            <button className="lb-btn lb-btn--pri mt-3 border rounded px-3 py-1.5" disabled={!allPicked || !packed} onClick={markShipped}>Mark as shipped</button>
          </Card>
          <Card title="Shipping address">
            <pre className="text-xs bg-gray-50 p-2 rounded">{JSON.stringify(o.shippingAddress||{},null,2)}</pre>
          </Card>
        </div>
      </div>
    </AdminPage>
  )
}
