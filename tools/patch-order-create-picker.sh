#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
CLIENT="$ROOT/app/admin/orders/new/OrderCreate.client.tsx"

if [ ! -f "$ROOT/src/lib/orders.ts" ]; then
  echo "✗ Fant ikke src/lib/orders.ts. Lag den først (du har sannsynligvis allerede gjort det i en tidligere runde)."
  exit 1
fi

echo "→ Skriver $CLIENT"
mkdir -p "$(dirname "$CLIENT")"

cat > "$CLIENT" <<'TSX'
'use client'

import React from 'react'
import { AdminPage } from '@/src/components/AdminPage'
import { apiCreateOrder } from '@/src/lib/orders'

type Product = {
  id?: string
  _id?: string
  name?: string
  sku?: string
  price?: number
  stock?: number
}

type Line = {
  productId?: string
  sku?: string
  name: string
  price: number
  qty: number
}

type Customer = {
  id?: string
  _id?: string
  name?: string
  email?: string
  phone?: string
}

function normId(p: any) { return p?.id || p?._id || '' }

function normalizeProducts(raw: any): Product[] {
  const arr = Array.isArray(raw) ? raw : (raw?.items ?? raw?.data ?? [])
  return (arr || []).map((p: any) => ({
    id: p?.id ?? p?._id,
    _id: p?._id,
    name: p?.name ?? p?.title ?? 'Uten navn',
    sku: p?.sku ?? p?.code ?? undefined,
    price: typeof p?.price === 'number' ? p.price :
           typeof p?.unitPrice === 'number' ? p.unitPrice :
           typeof p?.salesPrice === 'number' ? p.salesPrice : 0,
    stock: typeof p?.stock === 'number' ? p.stock :
           typeof p?.available === 'number' ? p.available :
           typeof p?.qty === 'number' ? p.qty : undefined,
  }))
}

async function fetchProducts(q: string) {
  const params = new URLSearchParams()
  params.set('page', '1')
  params.set('size', '50')
  if (q.trim()) params.set('q', q.trim())
  const res = await fetch(`/api/products?${params.toString()}`, { cache: 'no-store' })
  if (!res.ok) return []
  const json = await res.json()
  return normalizeProducts(json)
}

export default function OrderCreate(){
  const [busy, setBusy] = React.useState(false)
  const [notes, setNotes] = React.useState('')
  const [customer, setCustomer] = React.useState<Customer>({ name: '', email: '', phone: '' })
  const [lines, setLines] = React.useState<Line[]>([])

  // Produkt-søk
  const [q, setQ] = React.useState('')
  const [results, setResults] = React.useState<Product[]>([])
  const [searching, setSearching] = React.useState(false)

  // Egendefinert linje
  const [customName, setCustomName] = React.useState('')
  const [customPrice, setCustomPrice] = React.useState<number | ''>('')
  const [customQty, setCustomQty] = React.useState<number | ''>('')

  // Debounce søk
  React.useEffect(() => {
    let alive = true
    const t = setTimeout(async () => {
      setSearching(true)
      try {
        const list = await fetchProducts(q)
        if (!alive) return
        setResults(list)
      } catch {
        if (!alive) return
        setResults([])
      } finally {
        if (alive) setSearching(false)
      }
    }, 250)
    return () => { alive = false; clearTimeout(t) }
  }, [q])

  const addProductLine = (p: Product) => {
    const id = normId(p)
    const existingIx = lines.findIndex(l => l.productId === id || (l.sku && l.sku === p.sku))
    if (existingIx >= 0) {
      const copy = [...lines]
      copy[existingIx] = { ...copy[existingIx], qty: copy[existingIx].qty + 1 }
      setLines(copy)
      return
    }
    setLines([
      ...lines,
      {
        productId: id || undefined,
        sku: p.sku,
        name: p.name || 'Uten navn',
        price: p.price ?? 0,
        qty: 1
      }
    ])
  }

  const addCustomLine = () => {
    const price = Number(customPrice || 0)
    const qty = Number(customQty || 1)
    if (!customName.trim()) {
      (window as any).lbToast?.('Skriv inn navn for egendefinert linje')
      return
    }
    if (!(price >= 0)) {
      (window as any).lbToast?.('Pris må være et tall')
      return
    }
    if (!(qty > 0)) {
      (window as any).lbToast?.('Antall må være > 0')
      return
    }
    setLines([...lines, { name: customName.trim(), price, qty }])
    setCustomName('')
    setCustomPrice('')
    setCustomQty('')
  }

  const updateLine = (ix: number, patch: Partial<Line>) => {
    const copy = [...lines]
    copy[ix] = { ...copy[ix], ...patch }
    setLines(copy)
  }

  const removeLine = (ix: number) => {
    const copy = [...lines]
    copy.splice(ix, 1)
    setLines(copy)
  }

  const total = lines.reduce((s, l) => s + (l.price || 0) * (l.qty || 0), 0)

  const handleCreate = async () => {
    try {
      setBusy(true)
      const out = await apiCreateOrder({ customer, lines, notes })
      ;(window as any).lbToast?.('Ordre opprettet')
      const id = (out as any)?.id ?? (out as any)?._id ?? (out as any)?.orderId
      if (id) location.href = `/admin/orders/${id}`
    } catch (e: any) {
      console.error(e)
      ;(window as any).lbToast?.(e?.message || 'Kunne ikke opprette ordre')
    } finally {
      setBusy(false)
    }
  }

  return (
    <AdminPage title="Ny ordre">
      <div className="p-4 grid md:grid-cols-3 gap-4">
        {/* Kolonne 1: Kundeinfo */}
        <div className="space-y-2 border rounded p-3">
          <div className="font-medium">Kunde</div>
          <input
            className="w-full border rounded px-3 py-2"
            placeholder="Navn"
            value={customer.name||''}
            onChange={e=>setCustomer({...customer, name:e.target.value})}
          />
          <input
            className="w-full border rounded px-3 py-2"
            placeholder="E-post"
            value={customer.email||''}
            onChange={e=>setCustomer({...customer, email:e.target.value})}
          />
          <input
            className="w-full border rounded px-3 py-2"
            placeholder="Telefon"
            value={customer.phone||''}
            onChange={e=>setCustomer({...customer, phone:e.target.value})}
          />
          <textarea
            className="w-full border rounded px-3 py-2"
            placeholder="Notater"
            value={notes}
            onChange={e=>setNotes(e.target.value)}
            rows={4}
          />
        </div>

        {/* Kolonne 2: Produkt-søk + custom linjer */}
        <div className="space-y-3 border rounded p-3">
          <div className="font-medium">Produkter</div>
          <input
            className="w-full border rounded px-3 py-2"
            placeholder="Søk produkter (navn/SKU)…"
            value={q}
            onChange={e=>setQ(e.target.value)}
          />
          {searching && <div className="text-xs text-neutral-500">Søker…</div>}
          {!searching && results.length === 0 && q.trim() && (
            <div className="text-xs text-neutral-500">Ingen produkter funnet</div>
          )}
          {!searching && results.length > 0 && (
            <div className="border rounded divide-y max-h-64 overflow-auto">
              {results.map((p, ix) => (
                <div key={normId(p) || p.sku || ix} className="p-2 flex items-center justify-between">
                  <div className="min-w-0">
                    <div className="truncate font-medium">{p.name}</div>
                    <div className="text-xs text-neutral-500">{p.sku || '–'} · {p.price ?? 0} kr {typeof p.stock==='number' ? `· på lager: ${p.stock}` : ''}</div>
                  </div>
                  <button
                    className="px-3 py-1 rounded bg-neutral-900 text-white text-xs"
                    onClick={()=>addProductLine(p)}
                  >
                    Legg til
                  </button>
                </div>
              ))}
            </div>
          )}

          <div className="font-medium pt-2">Egendefinert linje</div>
          <div className="grid grid-cols-6 gap-2 items-center">
            <input
              className="col-span-3 border rounded px-3 py-2"
              placeholder="Navn"
              value={customName}
              onChange={e=>setCustomName(e.target.value)}
            />
            <input
              className="col-span-1 border rounded px-3 py-2"
              placeholder="Pris"
              inputMode="decimal"
              value={customPrice}
              onChange={e=>setCustomPrice(e.target.value as any)}
            />
            <input
              className="col-span-1 border rounded px-3 py-2"
              placeholder="Antall"
              inputMode="numeric"
              value={customQty}
              onChange={e=>setCustomQty(e.target.value as any)}
            />
            <button
              className="col-span-1 px-3 py-2 rounded bg-neutral-900 text-white text-xs"
              onClick={addCustomLine}
            >
              Legg til
            </button>
          </div>
        </div>

        {/* Kolonne 3: Linjer */}
        <div className="space-y-2 border rounded p-3">
          <div className="font-medium">Linjer</div>
          {lines.length === 0 && <div className="text-sm text-neutral-500">Ingen linjer</div>}
          {lines.map((l, ix) => (
            <div key={ix} className="grid grid-cols-6 gap-2 items-center">
              <div className="col-span-3">
                <div className="text-sm">{l.name}</div>
                <div className="text-xs text-neutral-500">{l.sku || l.productId || 'custom'}</div>
              </div>
              <input
                className="col-span-1 border rounded px-2 py-1 text-sm"
                inputMode="decimal"
                value={l.price}
                onChange={e=>updateLine(ix, { price: Number(e.target.value || 0) })}
              />
              <input
                className="col-span-1 border rounded px-2 py-1 text-sm"
                inputMode="numeric"
                value={l.qty}
                onChange={e=>updateLine(ix, { qty: Math.max(1, Number(e.target.value || 1)) })}
              />
              <button
                className="col-span-1 px-2 py-1 rounded border text-xs"
                onClick={()=>removeLine(ix)}
              >
                Fjern
              </button>
            </div>
          ))}
          <div className="pt-2 text-sm font-medium">Sum: {total} kr</div>
          <button
            className="w-full mt-2 px-3 py-2 rounded bg-neutral-900 text-white disabled:opacity-50"
            onClick={handleCreate}
            disabled={busy || lines.length === 0}
          >
            {busy ? 'Oppretter…' : 'Opprett ordre'}
          </button>
        </div>
      </div>
    </AdminPage>
  )
}
TSX

echo "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true
echo "✓ Ferdig. Start dev-server på nytt (npm run dev)."
