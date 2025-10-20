#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
CLIENT="$ROOT/app/admin/orders/new/OrderCreate.client.tsx"

echo "→ Skriver $CLIENT"
mkdir -p "$(dirname "$CLIENT")"
cat > "$CLIENT" <<'TSX'
'use client'

import React, { useMemo, useState } from 'react'
import { apiCreateOrder, type CreateOrderPayload } from '@/src/lib/orders'

type Line = {
  productId: string
  variantId?: string
  qty: number
  price?: number
  title?: string
}

type Customer = {
  id?: string
  email?: string
  name?: string
  phone?: string
}

export default function OrderCreate() {
  const [busy, setBusy] = useState(false)
  const [notes, setNotes] = useState('')
  const [customer, setCustomer] = useState<Customer>({})
  const [lines, setLines] = useState<Line[]>([
    { productId: '', qty: 1, price: undefined, title: '' }
  ])

  const isValid = useMemo(() => {
    if (!customer?.email && !customer?.id) return false
    if (lines.length === 0) return false
    for (const l of lines) {
      if (!l.productId || !l.qty) return false
    }
    return true
  }, [customer, lines])

  const setLine = (ix: number, patch: Partial<Line>) =>
    setLines(prev => prev.map((l, i) => (i === ix ? { ...l, ...patch } : l)))

  const addLine = () =>
    setLines(prev => [...prev, { productId: '', qty: 1, price: undefined, title: '' }])

  const removeLine = (ix: number) =>
    setLines(prev => prev.filter((_, i) => i !== ix))

  async function handleCreate() {
    try {
      setBusy(true)
      const payload: CreateOrderPayload = {
        customer: customer as any,
        lines: lines.map(l => ({
          productId: String(l.productId),
          variantId: l.variantId ? String(l.variantId) : undefined,
          qty: Number(l.qty) || 1,
          price: l.price != null && l.price !== ('' as any) ? Number(l.price) : undefined,
        })),
        notes: notes?.trim() ? notes.trim() : undefined,
      }
      const out = await apiCreateOrder(payload)
      ;(window as any).lbToast?.('Ordre opprettet')
      const id = out?.id ?? out?._id ?? out?.orderId
      if (id) {
        location.href = `/admin/orders/${id}`
      } else {
        // Fallback – gå til ordreliste
        location.href = '/admin/orders'
      }
    } catch (e) {
      console.error(e)
      ;(window as any).lbToast?.('Kunne ikke opprette ordre')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="p-4 space-y-6">
      <h1 className="text-lg font-semibold">Ny ordre</h1>

      {/* Kunde */}
      <div className="space-y-2">
        <div className="font-medium">Kunde</div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
          <input
            className="border rounded px-2 py-1"
            placeholder="Kunde-ID (valgfritt)"
            value={customer.id || ''}
            onChange={e => setCustomer(c => ({ ...c, id: e.target.value }))}
          />
          <input
            className="border rounded px-2 py-1"
            placeholder="E-post"
            value={customer.email || ''}
            onChange={e => setCustomer(c => ({ ...c, email: e.target.value }))}
          />
          <input
            className="border rounded px-2 py-1"
            placeholder="Navn (valgfritt)"
            value={customer.name || ''}
            onChange={e => setCustomer(c => ({ ...c, name: e.target.value }))}
          />
        </div>
      </div>

      {/* Linjer */}
      <div className="space-y-2">
        <div className="font-medium">Linjer</div>
        <div className="space-y-2">
          {lines.map((l, ix) => (
            <div key={ix} className="grid grid-cols-1 md:grid-cols-6 gap-2 items-center">
              <input
                className="border rounded px-2 py-1 md:col-span-2"
                placeholder="Produkt-ID"
                value={l.productId}
                onChange={e => setLine(ix, { productId: e.target.value })}
              />
              <input
                className="border rounded px-2 py-1"
                placeholder="Variant-ID (valgfritt)"
                value={l.variantId || ''}
                onChange={e => setLine(ix, { variantId: e.target.value })}
              />
              <input
                className="border rounded px-2 py-1"
                placeholder="Antall"
                type="number"
                min={1}
                value={l.qty}
                onChange={e => setLine(ix, { qty: Number(e.target.value) || 1 })}
              />
              <input
                className="border rounded px-2 py-1"
                placeholder="Pris (valgfritt)"
                type="number"
                step="0.01"
                value={l.price ?? ''}
                onChange={e => {
                  const v = e.target.value
                  setLine(ix, { price: v === '' ? undefined : Number(v) })
                }}
              />
              <button
                type="button"
                className="border px-3 py-1 rounded"
                onClick={() => removeLine(ix)}
              >
                Fjern
              </button>
            </div>
          ))}
        </div>
        <button type="button" className="border px-3 py-1 rounded" onClick={addLine}>
          + Legg til linje
        </button>
      </div>

      {/* Notater */}
      <div className="space-y-2">
        <div className="font-medium">Notater</div>
        <textarea
          className="border rounded px-2 py-1 w-full min-h-[100px]"
          placeholder="Valgfritt"
          value={notes}
          onChange={e => setNotes(e.target.value)}
        />
      </div>

      <div>
        <button
          type="button"
          disabled={!isValid || busy}
          className={
            'px-4 py-2 rounded ' +
            (isValid && !busy
              ? 'bg-black text-white'
              : 'bg-neutral-200 text-neutral-500 cursor-not-allowed')
          }
          onClick={handleCreate}
        >
          {busy ? 'Oppretter…' : 'Opprett ordre'}
        </button>
      </div>
    </div>
  )
}
TSX

echo "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true

echo "✓ Ferdig. Start dev-server (npm run dev) og test Ny ordre."