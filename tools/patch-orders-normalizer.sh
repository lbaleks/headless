#!/usr/bin/env bash
set -euo pipefail

FILE="app/admin/orders/page.tsx"

if [ ! -f "$FILE" ]; then
  echo "Fant ikke $FILE. Har du kjørt install-admin-orders.sh først?"
  exit 1
fi

cat > "$FILE" <<'TS'
// @patched: robust normalisering av /api/orders
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

function pick<T=any>(obj:any, keys:string[]): T|undefined {
  for (const k of keys) {
    if (obj && obj[k] !== undefined && obj[k] !== null) return obj[k]
  }
  return undefined
}

function normalizeOrders(json:any): OrderRow[] {
  // Finn listefelt
  let list: any[] = []
  if (Array.isArray(json)) list = json
  else list =
    json?.items ?? json?.orders ?? json?.data ?? json?.results ?? json?.content ?? json?.rows ?? []

  if (!Array.isArray(list)) list = []

  // Map til vårt UI-format
  return list.map((o:any, ix:number) => {
    const id = String(
      pick(o, ['id','_id','orderId']) ?? ix
    )
    const number = pick(o, ['number','orderNumber','no','reference','ref']) ?? id
    const status = String(pick(o, ['status','state','orderStatus']) ?? '') || undefined

    const totalRaw =
      pick(o, ['total','grandTotal','amount','priceTotal','sum','grossTotal']) ??
      (pick(o, ['subtotal']) ?? 0) + (pick(o, ['shipping']) ?? 0) + (pick(o, ['tax','vat']) ?? 0)

    const currency =
      pick(o, ['currency','curr','currencyCode','ccy']) ?? 'NOK'

    const customer =
      pick(o, ['customer','buyer','client','user']) ?? {}

    const createdAt =
      pick(o, ['createdAt','created','created_at','date','placedAt','placed_at','ts'])

    // Tall kan komme i øre/cent – behold som gitt, UI håndterer begge
    const total = typeof totalRaw === 'string' ? Number(totalRaw) : (totalRaw ?? 0)

    return {
      id, number, status, total, currency: String(currency),
      customer: {
        name: pick(customer, ['name','fullName','displayName']) as any,
        email: pick(customer, ['email','mail']) as any,
      },
      createdAt
    }
  })
}

const once = { logged:false }

export default function OrdersPage() {
  const [rows, setRows] = useState<OrderRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let abort = false
    ;(async () => {
      try {
        const url = '/api/orders?page=1&size=9999'
        const res = await fetch(url, { cache: 'no-store' })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const json = await res.json()

        if (!once.logged) {
          // Hjelpsom debug i dev – vis kun én gang
          console.debug('[OrdersPage] rå /api/orders-respons:', json)
          once.logged = true
        }

        if (abort) return
        const items = normalizeOrders(json)
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
                      <td className="px-3 py-2 text-right">
                        {new Intl.NumberFormat('nb-NO', { style: 'currency', currency }).format((total/100) || total)}
                      </td>
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

echo "→ Rydder .next-cache"
rm -rf .next .next-cache 2>/dev/null || true

echo "✓ Ferdig. Start dev-server på nytt (npm run dev)"
