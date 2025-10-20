#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

say(){ echo "→ $*"; }

say "Oppretter mapper…"
mkdir -p "$ROOT/app/api/orders/[id]"
mkdir -p "$ROOT/app/admin/orders/[id]"
mkdir -p "$ROOT/src/lib"

API_FILE="$ROOT/app/api/orders/[id]/route.ts"
PAGE_FILE="$ROOT/app/admin/orders/[id]/page.tsx"
CLIENT_FILE="$ROOT/app/admin/orders/[id]/OrderDetail.client.tsx"
ORDERS_LIB="$ROOT/src/lib/orders.ts"

say "Skriver $ORDERS_LIB"
cat > "$ORDERS_LIB" <<'TS'
export type OrderStatus = 'draft' | 'submitted' | 'paid' | 'fulfilled' | 'cancelled'

export type OrderLine = { sku?: string; name: string; qty: number; price: number }
export type Order = {
  id: string
  createdAt: string
  customer?: { id?: string; name?: string; email?: string }
  lines: OrderLine[]
  notes?: string
  status: OrderStatus
  events?: { id: string; text: string; ts: string; tone?: 'info'|'success'|'warn'|'danger'|'neutral' }[]
}

const mem: { orders: Record<string, Order> } = (global as any).__ORDERS__ ?? { orders: {} }
;(global as any).__ORDERS__ = mem

export function getOrder(id: string){ return mem.orders[id] }
export function upsertOrder(o: Order){ mem.orders[o.id]=o; return mem.orders[o.id] }
export function patchOrder(id: string, patch: Partial<Pick<Order,'status'|'notes'|'lines'>>){
  const cur = getOrder(id); if(!cur) return
  const next: Order = { ...cur, ...patch }; mem.orders[id]=next; return next
}
export function addEvent(id: string, text: string, tone?: Order['events'][number]['tone']){
  const cur = getOrder(id); if(!cur) return
  const ev = { id: crypto.randomUUID(), text, ts: new Date().toISOString(), tone }
  mem.orders[id] = { ...cur, events: [...(cur.events||[]), ev] }
  return ev
}
export function toOrderDTO(o: Order){
  return { id:o.id, createdAt:o.createdAt, status:o.status, customer:o.customer??null,
    lines:o.lines??[], notes:o.notes??'', events:o.events??[] }
}
TS

say "Skriver $API_FILE"
cat > "$API_FILE" <<'TS'
import { NextResponse } from 'next/server'
import { getOrder, patchOrder, addEvent, toOrderDTO, type OrderLine, type OrderStatus } from '@/src/lib/orders'

export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const order = getOrder(id)
  if(!order) return NextResponse.json({ error:'Not found' }, { status:404 })
  return NextResponse.json(toOrderDTO(order))
}

export async function PATCH(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const body = await req.json().catch(()=>({}))
  const patch: {
    status?: OrderStatus; notes?: string; lines?: OrderLine[]
    eventText?: string; eventTone?: 'info'|'success'|'warn'|'danger'|'neutral'
  } = body || {}
  const updated = patchOrder(id, { status:patch.status, notes:patch.notes, lines:patch.lines })
  if(!updated) return NextResponse.json({ error:'Not found' }, { status:404 })
  if(patch.eventText) addEvent(id, patch.eventText, patch.eventTone)
  return NextResponse.json(toOrderDTO(updated))
}
TS

say "Skriver $PAGE_FILE"
cat > "$PAGE_FILE" <<'TS'
import React from 'react'
import { AdminPage } from '@/src/components/AdminPage'
import OrderDetail from './OrderDetail.client'

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return (
    <AdminPage title={`Order #${id}`}>
      <OrderDetail id={id} />
    </AdminPage>
  )
}
TS

say "Skriver $CLIENT_FILE"
cat > "$CLIENT_FILE" <<'TS'
'use client'
import React from 'react'
import Link from 'next/link'

type Tone = 'info'|'success'|'warn'|'danger'|'neutral'
type OrderStatus = 'draft'|'submitted'|'paid'|'fulfilled'|'cancelled'
type OrderLine = { sku?: string; name: string; qty: number; price: number }
type Event = { id: string; text: string; ts: string; tone?: Tone }
type OrderDTO = { id:string; createdAt:string; status:OrderStatus; customer?:{id?:string;name?:string;email?:string}|null; lines:OrderLine[]; notes?:string; events:Event[] }

function currency(n:number){ return new Intl.NumberFormat(undefined,{style:'currency',currency:'NOK'}).format(n) }
function cx(...xs:(string|false|undefined|null)[]){ return xs.filter(Boolean).join(' ') }

export default function OrderDetail({ id}:{id:string }){
  const [data,setData] = React.useState<OrderDTO|null>(null)
  const [tab,setTab] = React.useState<'summary'|'lines'|'events'>('summary')
  const [busy,setBusy] = React.useState(false)
  const [err,setErr] = React.useState<string|null>(null)

  const load = React.useCallback(async ()=>{
    setErr(null)
    const res = await fetch(`/api/orders/${id}`, { cache:'no-store' })
    if(!res.ok){ setErr(`HTTP ${res.status}`); setData(null); return }
    setData(await res.json())
  },[id])

  React.useEffect(()=>{ load() },[load])

  async function patch(p: Partial<Pick<OrderDTO,'status'|'notes'|'lines'>> & {eventText?:string;eventTone?:Tone}){
    setBusy(true)
    try{
      const res = await fetch(`/api/orders/${id}`,{
        method:'PATCH', headers:{'content-type':'application/json'}, body:JSON.stringify(p)
      })
      if(!res.ok) throw new Error(`HTTP ${res.status}`)
      setData(await res.json())
    }catch(e){ console.error(e); (window as any).lbToast?.('Kunne ikke lagre') }finally{ setBusy(false) }
  }

  function total(){ return (data?.lines||[]).reduce((s,l)=>s+l.qty*l.price,0) }
  function addLine(){ if(!data) return; patch({ lines:[...data.lines,{name:'Ny vare',qty:1,price:0}], eventText:'La til varelinje', eventTone:'info' }) }
  function updateLine(ix:number, pl:Partial<OrderLine>){ if(!data) return; patch({ lines:data.lines.map((l,i)=>i===ix?{...l,...pl}:l) }) }
  function removeLine(ix:number){ if(!data) return; patch({ lines:data.lines.filter((_,i)=>i!==ix), eventText:'Fjernet varelinje', eventTone:'warn' }) }

  if(err) return <div className="p-4"><div className="text-red-700 text-sm">Feil: {err}</div><button className="btn btn-sm mt-2" onClick={load}>Prøv igjen</button></div>
  if(!data) return <div className="p-6">Laster…</div>

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-lg font-semibold">Ordre #{data.id}</div>
          <div className="text-sm text-neutral-500">Opprettet {new Date(data.createdAt).toLocaleString()}</div>
        </div>
        <div className="flex items-center gap-2">
          <select className="border rounded px-2 py-1 text-sm" value={data.status} disabled={busy}
            onChange={e=>patch({ status:e.target.value as OrderStatus, eventText:`Status: ${e.target.value}`, eventTone:'info' })}>
            {['draft','submitted','paid','fulfilled','cancelled'].map(s=><option key={s} value={s}>{s}</option>)}
          </select>
          <button className="btn btn-sm" onClick={load} disabled={busy}>Oppfrisk</button>
        </div>
      </div>

      <div className="grid md:grid-cols-3 gap-4">
        <div className="p-4 rounded border bg-white md:col-span-2">
          <div className="font-medium mb-1">Kunde</div>
          {data.customer?.id ? (
            <div className="text-sm">
              <Link href={`/admin/customers/${data.customer.id}`} className="text-blue-600 hover:underline">
                {data.customer.name || 'Uten navn'}
              </Link>
              <div className="text-neutral-500">{data.customer.email}</div>
            </div>
          ) : <div className="text-sm text-neutral-500">Ingen kunde knyttet</div>}
        </div>
        <div className="p-4 rounded border bg-white">
          <div className="font-medium mb-1">Totalt</div>
          <div className="text-2xl">{currency(total())}</div>
        </div>
      </div>

      <div className="border-b">
        {(['summary','lines','events'] as const).map(t=>(
          <button key={t} className={cx('px-3 py-2 text-sm mr-1 rounded-t', t===tab?'bg-neutral-900 text-white':'hover:bg-neutral-100')} onClick={()=>setTab(t)}>
            {t==='summary'?'Oppsummering':t==='lines'?'Linjer':'Hendelser'}
          </button>
        ))}
      </div>

      {tab==='summary' && (
        <div className="p-4 rounded border bg-white space-y-3">
          <div>
            <div className="text-sm font-medium mb-1">Notater</div>
            <textarea className="w-full border rounded p-2 text-sm" rows={4}
              value={data.notes||''} onChange={e=>patch({ notes:e.target.value })}/>
          </div>
          <div className="text-sm text-neutral-500">Ordre-ID: {data.id} • Opprettet: {new Date(data.createdAt).toLocaleString()}</div>
        </div>
      )}

      {tab==='lines' && (
        <div className="p-4 rounded border bg-white">
          <div className="flex justify-between items-center mb-3">
            <div className="font-medium">Varelinjer</div>
            <button className="btn btn-sm" onClick={addLine} disabled={busy}>Legg til vare</button>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead className="bg-neutral-50 text-neutral-600">
                <tr>
                  <th className="text-left p-2 w-[28%]">Navn</th>
                  <th className="text-left p-2 w-[18%]">SKU</th>
                  <th className="text-right p-2 w-[12%]">Antall</th>
                  <th className="text-right p-2 w-[18%]">Pris</th>
                  <th className="text-right p-2 w-[18%]">Sum</th>
                  <th className="p-2 w-[6%]"></th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {data.lines.map((l,ix)=>(
                  <tr key={ix}>
                    <td className="p-2"><input className="w-full border rounded px-2 py-1" value={l.name} onChange={e=>updateLine(ix,{name:e.target.value})}/></td>
                    <td className="p-2"><input className="w-full border rounded px-2 py-1" value={l.sku||''} onChange={e=>updateLine(ix,{sku:e.target.value})}/></td>
                    <td className="p-2 text-right"><input type="number" className="w-24 border rounded px-2 py-1 text-right" value={l.qty} onChange={e=>updateLine(ix,{qty:Math.max(0,Number(e.target.value||0))})}/></td>
                    <td className="p-2 text-right"><input type="number" className="w-28 border rounded px-2 py-1 text-right" value={l.price} onChange={e=>updateLine(ix,{price:Number(e.target.value||0)})}/></td>
                    <td className="p-2 text-right">{new Intl.NumberFormat(undefined,{style:'currency',currency:'NOK'}).format(l.qty*l.price)}</td>
                    <td className="p-2 text-right"><button className="text-red-600 hover:underline" onClick={()=>removeLine(ix)}>Fjern</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
            {data.lines.length===0 && <div className="text-sm text-neutral-500 p-2">Ingen varelinjer</div>}
          </div>
          <div className="mt-3 text-right text-sm"><span className="mr-2 text-neutral-500">Totalt:</span><span className="font-medium">{new Intl.NumberFormat(undefined,{style:'currency',currency:'NOK'}).format(total())}</span></div>
        </div>
      )}

      {tab==='events' && (
        <div className="p-4 rounded border bg-white">
          <div className="font-medium mb-2">Hendelser</div>
          <div className="space-y-3">
            {(data.events||[]).map(e=>(
              <div key={e.id} className="relative pl-4">
                <div className={cx('absolute left-0 top-1.5 h-2 w-2 rounded-full',
                  e.tone==='info'&&'bg-blue-600'|| e.tone==='success'&&'bg-green-600'|| e.tone==='warn'&&'bg-amber-500'|| e.tone==='danger'&&'bg-red-600'|| 'bg-neutral-300')}/>
                <div className="text-sm text-neutral-900">{e.text}</div>
                <div className="text-xs text-neutral-500">{new Date(e.ts).toLocaleString()}</div>
              </div>
            ))}
            {(!data.events || data.events.length===0) && <div className="text-sm text-neutral-500">Ingen hendelser enda</div>}
          </div>
        </div>
      )}
    </div>
  )
}
TS

say "Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true

echo "✓ Ferdig. Start dev-server på nytt (npm run dev / yarn dev / pnpm dev). Gå til /admin/orders/<id>."