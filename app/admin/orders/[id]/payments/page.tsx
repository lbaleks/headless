'use client';
import React,{useEffect,useState} from 'react'
import { useParams } from 'next/navigation'
import AdminPage from '@/components/AdminPage'
import RecordHeader from '@/components/ui/RecordHeader'
import { Card } from '@/components/ui/Card'


type Item={ sku:string; name:string; qty:number; price:number }
type Payment={ id:string; amount:number; status:string; createdAt?:string }
type Order={ id:string; status?:string; currency?:string; total:number; items:Item[]; paidTotal?:number; payments?:Payment[]; customer?:{name?:string} }

// Defensive money helper
function lbMoney(x:any){ return Number(x ?? 0) }

export default function OrderPayments(){
  const { id } = useParams<{id:string}>() as {id:string}
  const [o,setO]=useState<Order|null|undefined>(undefined)

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

  if(o===undefined) return <AdminPage title={'Order '+id}><div className="p-6">Loading…</div></AdminPage>
  if(o===null) return <AdminPage title={'Order '+id}><div className="p-6 text-red-600">Order not found.</div></AdminPage>

  const paid = Number(o.paidTotal||0)
  const total = Number(o.total||0)
  const outstanding = (total - paid)

  return (
    <AdminPage title={'Order '+id+' · Payments'}>
{(() => { const ototal=Number(o?.total??0), paid=Number(o?.paidTotal??0), refunded=Number(o?.refundedTotal??0), currency=(o?.currency||'NOK'); return (<></>) })()}

      <RecordHeader
        title={'Order '+id}
        subtitle={o.customer?.name? ('Customer: '+o.customer.name):undefined}
        status={{ text:(o.status||'processing') as any, tone: o.status==='complete'?'success':(o.status==='canceled'?'danger':'info') }}
        kpis={[
          {label:'Total', value: total.toFixed(2)+' '+(o.currency||'NOK')},
          {label:'Paid', value: Number((paid) ?? 0).toFixed(2)},
          {label:'Outstanding', value: outstanding.toFixed(2)},
          {label:'Items', value: String(o.items?.length||0)},
        ]}
      />
      <div className="mt-4 space-y-4">
        <Card title="Payments">
          <table className="min-w-full text-sm">
            <thead><tr><th className="p-2 text-left">ID</th><th className="p-2 text-right">Amount</th><th className="p-2">Status</th><th className="p-2">Created</th></tr></thead>
            <tbody>
              {(o.payments||[]).length? (o.payments||[]).map(p=>(
                <tr key={p.id} className="odd:bg-white even:bg-gray-50">
                  <td className="p-2 border-t font-mono">{p.id}</td>
                  <td className="p-2 border-t text-right">{Number(p.amount||0).toFixed(2)}</td>
                  <td className="p-2 border-t">{p.status}</td>
                  <td className="p-2 border-t">{p.createdAt||'—'}</td>
                </tr>
              )): <tr><td className="p-2 border-t text-neutral-500" colSpan={4}>No payments</td></tr>}
            </tbody>{(!Array.isArray($1)||!$1.length)&&<tbody><tr><td className="p-3 text-neutral-500" colSpan={99}>No rows</td></tr></tbody>}
          </table>
        </Card>
      </div>
    </AdminPage>
  )
}
