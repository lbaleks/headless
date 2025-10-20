#!/usr/bin/env bash
set -euo pipefail

echo "→ Oppretter mapper…"
mkdir -p app/admin/orders
mkdir -p app/admin/orders/[id]

echo "→ Skriver app/admin/orders/page.tsx"
cat > app/admin/orders/page.tsx <<'TS'
'use client'
import React, { useEffect, useState } from 'react'
import Link from 'next/link'
import { AdminPage } from '@/src/components/AdminPage'

type OrderRow = {
  id: string
  number?: string | number
  status?: string
  total?: number
  currency?: string
  customer?: { name?: string; email?: string }
  createdAt?: string | number | Date
}

export default function OrdersPage() {
  const [rows, setRows] = useState<OrderRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let abort = false
    ;(async () => {
      try {
        const res = await fetch('/api/orders?page=1&size=9999', { cache: 'no-store' })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const data = await res.json()
        if (abort) return
        const items: OrderRow[] = Array.isArray(data) ? data : (data?.items ?? [])
        setRows(items)
      } catch (e: any) {
        if (!abort) setError(e?.message || 'Kunne ikke laste ordre')
      }
    })()
    return () => { abort = true }
  }, [])

  return (
    <AdminPage title="Orders">
      {error && <div className="p-3 rounded bg-red-50 text-red-700 text-sm mb-4">{error}</div>}
      {!rows && !error && <div className="p-6 text-sm text-neutral-600">Laster…</div>}
      {rows && rows.length === 0 && <div className="p-6 text-sm text-neutral-600">Ingen ordre funnet.</div>}
      {rows && rows.length > 0 && (
        <div className="p-4">
          <div className="overflow-x-auto border rounded">
            <table className="min-w-[720px] w-full text-sm">
              <thead className="bg-neutral-50 text-neutral-700">
                <tr>
                  <th className="text-left px-3 py-2">Ordre</th>
                  <th className="text-left px-3 py-2">Kunde</th>
                  <th className="text-left px-3 py-2">Status</th>
                  <th className="text-right px-3 py-2">Total</th>
                  <th className="text-left px-3 py-2">Dato</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((o) => {
                  const num = o.number ?? o.id
                  const total = typeof o.total === 'number' ? o.total : 0
                  const currency = o.currency || 'NOK'
                  const dt = o.createdAt ? new Date(o.createdAt) : null
                  return (
                    <tr key={o.id} className="border-t hover:bg-neutral-50">
                      <td className="px-3 py-2">
                        <Link className="text-blue-600 hover:underline" href={`/admin/orders/${encodeURIComponent(o.id)}`}>
                          #{String(num)}
                        </Link>
                      </td>
                      <td className="px-3 py-2">{o.customer?.name || o.customer?.email || <span className="text-neutral-400">—</span>}</td>
                      <td className="px-3 py-2">{o.status || <span className="text-neutral-400">—</span>}</td>
                      <td className="px-3 py-2 text-right">{new Intl.NumberFormat('nb-NO', { style: 'currency', currency }).format(total/100 || total)}</td>
                      <td className="px-3 py-2">{dt ? dt.toLocaleString() : <span className="text-neutral-400">—</span>}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </AdminPage>
  )
}
TS

echo "→ Skriver app/admin/orders/[id]/page.tsx"
cat > app/admin/orders/[id]/page.tsx <<'TS'
import React from 'react'
import OrderDetail from './OrderDetail.client'

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return <OrderDetail id={id} />
}
TS

echo "→ Skriver app/admin/orders/[id]/OrderDetail.client.tsx"
cat > app/admin/orders/[id]/OrderDetail.client.tsx <<'TS'
'use client'
import React, { useEffect, useMemo, useState } from 'react'
import { AdminPage } from '@/src/components/AdminPage'

type OrderLine = {
  id?: string
  sku?: string
  name?: string
  qty?: number
  unitPrice?: number
  total?: number
}

type OrderLike = {
  id: string
  number?: string | number
  status?: string
  currency?: string
  createdAt?: string | number | Date
  customer?: { name?: string; email?: string; phone?: string }
  shippingAddress?: Partial<Record<'line1'|'line2'|'city'|'postalCode'|'country', string>>
  billingAddress?: Partial<Record<'line1'|'line2'|'city'|'postalCode'|'country', string>>
  lines?: OrderLine[]
  subtotal?: number
  shipping?: number
  tax?: number
  total?: number
  events?: { id?: string; text?: string; ts?: string | number | Date; tone?: 'info'|'success'|'warn'|'danger'|'neutral' }[]
}

export default function OrderDetail({ id }: { id: string }) {
  const [order, setOrder] = useState<OrderLike | null>(null)
  const [tab, setTab] = useState<'summary'|'items'|'events'>('summary')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let abort = false
    ;(async () => {
      try {
        const res = await fetch(`/api/orders/${encodeURIComponent(id)}`, { cache: 'no-store' })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const data = await res.json()
        if (!abort) setOrder(data ?? null)
      } catch (e: any) {
        if (!abort) setError(e?.message || 'Kunne ikke laste ordre')
      }
    })()
    return () => { abort = true }
  }, [id])

  const currency = order?.currency || 'NOK'
  const fmt = (n?: number) => new Intl.NumberFormat('nb-NO', { style: 'currency', currency }).format((n ?? 0)/100 || (n ?? 0))
  const lines = order?.lines ?? []

  const totals = useMemo(() => {
    const sub = order?.subtotal ?? lines.reduce((s, l) => s + (l.total ?? (l.qty ?? 0) * (l.unitPrice ?? 0)), 0)
    const ship = order?.shipping ?? 0
    const tax = order?.tax ?? 0
    const tot = order?.total ?? (sub + ship + tax)
    return { sub, ship, tax, tot }
  }, [order, lines])

  return (
    <AdminPage
      title={`Order #${order?.number ?? id}`}
      actions={
        <div className="flex gap-2">
          <button className="px-3 py-1.5 rounded bg-neutral-900 text-white text-sm" onClick={()=>location.reload()}>Oppfrisk</button>
        </div>
      }
      tabs={[
        { key:'summary', label:'Oppsummering' },
        { key:'items',   label:'Linjer' },
        { key:'events',  label:'Hendelser' },
      ]}
      tab={tab}
      onTabChange={(k)=>setTab(k as any)}
    >
      {!order && !error && <div className="p-6 text-sm text-neutral-600">Laster…</div>}
      {error && <div className="p-3 rounded bg-red-50 text-red-700 text-sm mb-4">{error}</div>}

      {order && tab==='summary' && (
        <div className="p-4 grid md:grid-cols-3 gap-4">
          <div className="md:col-span-2 space-y-4">
            <div className="border rounded p-4">
              <div className="font-medium mb-2">Status</div>
              <div className="text-sm">{order.status ?? '—'}</div>
            </div>

            <div className="border rounded p-4">
              <div className="font-medium mb-3">Linjer</div>
              <div className="overflow-x-auto">
                <table className="min-w-[640px] w-full text-sm">
                  <thead className="bg-neutral-50 text-neutral-700">
                    <tr>
                      <th className="text-left px-3 py-2">Produkt</th>
                      <th className="text-left px-3 py-2">SKU</th>
                      <th className="text-right px-3 py-2">Antall</th>
                      <th className="text-right px-3 py-2">Pris</th>
                      <th className="text-right px-3 py-2">Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    {lines.map((l, ix)=>(
                      <tr key={l.id ?? ix} className="border-t">
                        <td className="px-3 py-2">{l.name ?? '—'}</td>
                        <td className="px-3 py-2">{l.sku ?? '—'}</td>
                        <td className="px-3 py-2 text-right">{l.qty ?? 0}</td>
                        <td className="px-3 py-2 text-right">{fmt(l.unitPrice)}</td>
                        <td className="px-3 py-2 text-right">{fmt(l.total ?? (l.qty ?? 0)*(l.unitPrice ?? 0))}</td>
                      </tr>
                    ))}
                    {lines.length===0 && (
                      <tr><td colSpan={5} className="px-3 py-4 text-center text-neutral-500">Ingen linjer</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <div className="space-y-4">
            <div className="border rounded p-4">
              <div className="font-medium mb-2">Totalsummer</div>
              <div className="text-sm grid grid-cols-2 gap-y-1">
                <div className="text-neutral-600">Subtotal</div><div className="text-right">{fmt(totals.sub)}</div>
                <div className="text-neutral-600">Frakt</div><div className="text-right">{fmt(totals.ship)}</div>
                <div className="text-neutral-600">MVA</div><div className="text-right">{fmt(totals.tax)}</div>
                <div className="border-t mt-2 pt-2 font-medium">Total</div><div className="border-t mt-2 pt-2 text-right font-medium">{fmt(totals.tot)}</div>
              </div>
            </div>

            <div className="border rounded p-4">
              <div className="font-medium mb-2">Kunde</div>
              <div className="text-sm">
                <div>{order.customer?.name ?? '—'}</div>
                <div className="text-neutral-600">{order.customer?.email ?? ''}</div>
                <div className="text-neutral-600">{order.customer?.phone ?? ''}</div>
              </div>
            </div>

            <div className="border rounded p-4">
              <div className="font-medium mb-2">Fakturering</div>
              <Addr a={order.billingAddress}/>
            </div>
            <div className="border rounded p-4">
              <div className="font-medium mb-2">Levering</div>
              <Addr a={order.shippingAddress}/>
            </div>
          </div>
        </div>
      )}

      {order && tab==='items' && (
        <div className="p-4">
          <div className="overflow-x-auto border rounded">
            <table className="min-w-[640px] w-full text-sm">
              <thead className="bg-neutral-50 text-neutral-700">
                <tr>
                  <th className="text-left px-3 py-2">Produkt</th>
                  <th className="text-left px-3 py-2">SKU</th>
                  <th className="text-right px-3 py-2">Antall</th>
                  <th className="text-right px-3 py-2">Pris</th>
                  <th className="text-right px-3 py-2">Total</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((l, ix)=>(
                  <tr key={l.id ?? ix} className="border-t">
                    <td className="px-3 py-2">{l.name ?? '—'}</td>
                    <td className="px-3 py-2">{l.sku ?? '—'}</td>
                    <td className="px-3 py-2 text-right">{l.qty ?? 0}</td>
                    <td className="px-3 py-2 text-right">{fmt(l.unitPrice)}</td>
                    <td className="px-3 py-2 text-right">{fmt(l.total ?? (l.qty ?? 0)*(l.unitPrice ?? 0))}</td>
                  </tr>
                ))}
                {lines.length===0 && (
                  <tr><td colSpan={5} className="px-3 py-4 text-center text-neutral-500">Ingen linjer</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {order && tab==='events' && (
        <div className="p-4 space-y-3">
          {(order.events ?? []).map((ev, ix)=>(
            <div key={ev.id ?? ix} className="relative pl-4">
              <div className={"absolute left-0 top-1.5 h-2 w-2 rounded-full "+({info:'bg-blue-600',success:'bg-green-600',warn:'bg-amber-500',danger:'bg-red-600',neutral:'bg-neutral-300'}[ev.tone || 'neutral'])}/>
              <div className="text-sm text-neutral-900">{ev.text ?? '—'}</div>
              <div className="text-xs text-neutral-500">{ev.ts ? new Date(ev.ts).toLocaleString() : ''}</div>
            </div>
          ))}
          {(order.events ?? []).length===0 && <div className="text-sm text-neutral-500">Ingen hendelser</div>}
        </div>
      )}
    </AdminPage>
  )
}

function Addr({a}:{a: any}){
  if(!a) return <div className="text-sm text-neutral-500">—</div>
  return (
    <div className="text-sm">
      <div>{a.line1}</div>
      {a.line2 && <div>{a.line2}</div>}
      <div>{[a.postalCode, a.city].filter(Boolean).join(' ')}</div>
      <div>{a.country}</div>
    </div>
  )
}
TS

echo "→ Rydder .next-cache"
rm -rf .next 2>/dev/null || true
rm -rf .next-cache 2>/dev/null || true

echo "✓ Ferdig. Start dev-server på nytt (npm run dev / yarn dev / pnpm dev)."
