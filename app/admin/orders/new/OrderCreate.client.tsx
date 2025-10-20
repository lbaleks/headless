'use client';
import React, { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'

type Customer = {
  id: number
  email: string
  firstname?: string
  lastname?: string
  name?: string
}
type Product = {
  id: number
  sku: string
  name: string
  price?: number
  tax_class_id?: string|number
  image?: string|null
}

type Line =
  | { kind:'product', sku:string, name:string, qty:number, price:number, productId:number }
  | { kind:'custom',  sku?:string, name:string, qty:number, price:number }

const MULT = Number(process.env.NEXT_PUBLIC_PRICE_MULTIPLIER || process.env.PRICE_MULTIPLIER || '1') || 1
const VAT = 0.25 // enkel mva for v1 – senere tar vi fra Magento tax_class

async function searchCustomers(q: string) {
  const url = `/api/customers?page=1&size=10&q=${encodeURIComponent(q)}`
  const res = await fetch(url, { cache: 'no-store' })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const data = await res.json()
  return (data.items || []) as Customer[]
}

async function searchProducts(q: string) {
  const url = `/api/products?page=1&size=10&q=${encodeURIComponent(q)}`
  const res = await fetch(url, { cache: 'no-store' })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const data = await res.json()
  return (data.items || []) as Product[]
}

// Placeholder – samme signatur som tidligere
async function apiCreateOrder(payload: { customer: Customer|null, lines: Line[], notes?: string, shipping?: number }) {
  const res = await fetch('/api/orders', {
    method: 'POST',
    headers: { 'content-type':'application/json' },
    body: JSON.stringify(payload),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return await res.json()
}

export default function OrderCreate() {
  const [busy, setBusy] = useState(false)
  const [notes, setNotes] = useState('')
  const [shipping, setShipping] = useState<number>(0)
  const [customer, setCustomer] = useState<Customer|null>(null)
  const [custQuery, setCustQuery] = useState('')
  const [custRes, setCustRes] = useState<Customer[] | null>(null)

  const [prodQuery, setProdQuery] = useState('')
  const [prodRes, setProdRes] = useState<Product[] | null>(null)

  const [lines, setLines] = useState<Line[]>([])

  // Søk – kunder
  useEffect(() => {
    let abort = false
    if (!custQuery.trim()) { setCustRes(null); return }
    ;(async () => {
      try {
        const out = await searchCustomers(custQuery.trim())
        if (!abort) setCustRes(out)
      } catch {
        if (!abort) setCustRes([])
      }
    })()
    return () => { abort = true }
  }, [custQuery])

  // Søk – produkter
  useEffect(() => {
    let abort = false
    if (!prodQuery.trim()) { setProdRes(null); return }
    ;(async () => {
      try {
        const out = await searchProducts(prodQuery.trim())
        if (!abort) setProdRes(out)
      } catch {
        if (!abort) setProdRes([])
      }
    })()
    return () => { abort = true }
  }, [prodQuery])

  const addProduct = (p: Product) => {
    const price = Math.round(((p.price ?? 0) * MULT) * 100) / 100
    setLines(prev => [...prev, { kind:'product', sku:p.sku, name:p.name, qty:1, price, productId: p.id }])
    setProdQuery('')
    setProdRes(null)
  }
  const addCustom = () => {
    setLines(prev => [...prev, { kind:'custom', name:'Custom vare', qty:1, price:0 }])
  }
  const updateLine = (ix:number, patch: Partial<Extract<Line,{kind:string}>>) => {
    setLines(prev => prev.map((l,i)=> i===ix ? ({...l, ...patch}) as Line : l))
  }
  const removeLine = (ix:number) => setLines(prev => prev.filter((_,i)=>i!==ix))

  const subEx = useMemo(()=> lines.reduce((s,l)=> s + (l.qty * l.price), 0), [lines])
  const tax   = useMemo(()=> Math.round((subEx * VAT) * 100)/100, [subEx])
  const total = useMemo(()=> Math.round((subEx + tax + (shipping||0)) * 100)/100, [subEx,tax,shipping])

  const handleCreate = async () => {
    try {
      setBusy(true)
      const out = await apiCreateOrder({ customer, lines, notes, shipping })
      ;(window as any).lbToast?.('Ordre opprettet')

      const id = out?.id ?? out?._id ?? out?.orderId ?? out?.increment_id
      if (id) location.href = `/admin/orders/${encodeURIComponent(String(id))}`
      else location.href = `/admin/orders`
    } catch (e:any) {
      console.error(e)
      alert(`Kunne ikke opprette ordre: ${e?.message || e}`)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="p-4 md:p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">Ny ordre</h1>
        <Link className="text-sm underline" href="/admin/orders">Tilbake</Link>
      </div>

      {/* Kunde */}
      <div className="bg-white rounded-xl shadow p-4 space-y-3">
        <div className="text-sm font-medium">Kunde</div>
        {customer ? (
          <div className="flex items-center justify-between gap-4">
            <div className="text-sm">
              <div className="font-medium">{customer.name || `${customer.firstname||''} ${customer.lastname||''}`.trim()}</div>
              <div className="text-neutral-500">{customer.email}</div>
            </div>
            <button className="text-xs px-2 py-1 rounded border" onClick={()=>setCustomer(null)}>Bytt</button>
          </div>
        ) : (
          <>
            <input
              className="w-full rounded border px-3 py-2 text-sm"
              placeholder="Søk kunde (navn eller e-post)…"
              value={custQuery}
              onChange={e=>setCustQuery(e.target.value)}
            />
            {!!custRes && (
              <div className="rounded border divide-y">
                {custRes.length===0 && <div className="p-2 text-sm text-neutral-500">Ingen kunder</div>}
                {custRes.map(c=>(
                  <button key={c.id} className="w-full text-left px-3 py-2 text-sm hover:bg-neutral-50"
                          onClick={()=>setCustomer(c)}>
                    <div className="font-medium">{c.name || `${c.firstname||''} ${c.lastname||''}`.trim()}</div>
                    <div className="text-neutral-500">{c.email}</div>
                  </button>
                ))}
              </div>
            )}
          </>
        )}
      </div>

      {/* Linjer */}
      <div className="bg-white rounded-xl shadow p-4 space-y-3">
        <div className="flex items-center justify-between">
          <div className="text-sm font-medium">Linjer</div>
          <button onClick={addCustom} className="text-xs px-2 py-1 rounded border">Legg til custom</button>
        </div>

        {/* Produktsøk */}
        <input
          className="w-full rounded border px-3 py-2 text-sm"
          placeholder="Søk produkt (navn, sku)…"
          value={prodQuery}
          onChange={e=>setProdQuery(e.target.value)}
        />
        {!!prodRes && (
          <div className="rounded border divide-y max-h-64 overflow-auto">
            {prodRes.length===0 && <div className="p-2 text-sm text-neutral-500">Ingen produkter</div>}
            {prodRes.map(p=>(
              <button key={p.id} className="w-full text-left px-3 py-2 text-sm hover:bg-neutral-50"
                      onClick={()=>addProduct(p)}>
                <div className="font-medium">{p.name}</div>
                <div className="text-neutral-500">{p.sku} • {(p.price ?? 0).toFixed(2)} → {(Math.round(((p.price ?? 0)*MULT)*100)/100).toFixed(2)}</div>
              </button>
            ))}
          </div>
        )}

        {/* Linjeeditor */}
        <div className="space-y-2">
          {lines.length===0 && <div className="text-sm text-neutral-500">Ingen linjer enda</div>}
          {lines.map((l,ix)=>(
            <div key={ix} className="grid grid-cols-12 gap-2 items-center">
              <div className="col-span-5">
                <input className="w-full rounded border px-3 py-2 text-sm"
                       value={l.name}
                       onChange={e=>updateLine(ix,{name:e.target.value})}/>
                <div className="text-[11px] text-neutral-500">{l.kind==='product' ? l.sku : 'custom'}</div>
              </div>
              <div className="col-span-2">
                <input type="number" min={1} className="w-full rounded border px-3 py-2 text-sm"
                       value={l.qty}
                       onChange={e=>updateLine(ix,{qty: Math.max(1, Number(e.target.value||1))})}/>
              </div>
              <div className="col-span-3">
                <input type="number" step="0.01" className="w-full rounded border px-3 py-2 text-sm"
                       value={l.price}
                       onChange={e=>updateLine(ix,{price: Number(e.target.value||0)})}/>
              </div>
              <div className="col-span-1 text-sm text-right">
                {(l.qty*l.price).toFixed(2)}
              </div>
              <div className="col-span-1 text-right">
                <button className="text-xs px-2 py-1 rounded border" onClick={()=>removeLine(ix)}>X</button>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Notat + frakt */}
      <div className="bg-white rounded-xl shadow p-4 space-y-3">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div className="md:col-span-2">
            <div className="text-sm font-medium mb-1">Notater</div>
            <textarea
              className="w-full rounded border px-3 py-2 text-sm min-h-[72px]"
              value={notes} onChange={e=>setNotes(e.target.value)} />
          </div>
          <div>
            <div className="text-sm font-medium mb-1">Frakt</div>
            <input type="number" step="0.01" className="w-full rounded border px-3 py-2 text-sm"
                   value={shipping} onChange={e=>setShipping(Number(e.target.value||0))}/>
          </div>
        </div>
      </div>

      {/* Totals */}
      <div className="bg-white rounded-xl shadow p-4 space-y-2">
        <div className="flex items-center justify-between text-sm">
          <div>Delsum (eks mva)</div><div>{subEx.toFixed(2)}</div>
        </div>
        <div className="flex items-center justify-between text-sm">
          <div>MVA (25%)</div><div>{tax.toFixed(2)}</div>
        </div>
        <div className="flex items-center justify-between text-sm">
          <div>Frakt</div><div>{(shipping||0).toFixed(2)}</div>
        </div>
        <div className="flex items-center justify-between font-semibold">
          <div>Totalt</div><div>{total.toFixed(2)}</div>
        </div>

        <div className="pt-3 flex gap-2">
          <button
            disabled={busy || lines.length===0}
            className="px-4 py-2 rounded bg-black text-white disabled:opacity-50"
            onClick={handleCreate}>
            {busy ? 'Lagrer…' : 'Opprett ordre'}
          </button>
          <div className="text-xs text-neutral-500">
            Pris-multiplikator: {MULT} (sett <code>NEXT_PUBLIC_PRICE_MULTIPLIER</code> i .env.local)
          </div>
        </div>
      </div>
    </div>
  )
}
