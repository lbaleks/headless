#!/usr/bin/env bash
set -euo pipefail

echo "→ Oppdaterer ProductDetail til å ha menyer og flere felter…"

# page.tsx (lar denne være enkel – bruker await params)
cat > app/admin/products/[id]/page.tsx <<'TSX'
import React from 'react'
import ProductDetail from './ProductDetail.client'

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return <ProductDetail id={id} />
}
TSX

# Ny, mer komplett klient-komponent med egen tabbar og flere felt
cat > app/admin/products/[id]/ProductDetail.client.tsx <<'TSX'
'use client'

import React, { useEffect, useState } from 'react'

// Robuste imports – funker både for named og default
let AdminFrame: any = ({ children }: any) => (
  <div className="max-w-6xl mx-auto p-6">{children}</div>
)
try {
  // prøv å hente AdminPage (named eller default)
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const mod = require('@/src/components/AdminPage')
  const Cand = (mod as any).AdminPage ?? (mod as any).default
  if (Cand) {
    AdminFrame = ({ children }: any) => <Cand title="Product">{children}</Cand>
  }
} catch {}

let BulkVariantEdit: any = null
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const mod = require('@/src/components/BulkVariantEdit')
  BulkVariantEdit = (mod as any).BulkVariantEdit ?? (mod as any).default ?? null
} catch {}

let VariantImages: any = null
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const mod = require('@/src/components/VariantImages')
  VariantImages = (mod as any).VariantImages ?? (mod as any).default ?? null
} catch {}

type VariantLike = {
  id?: string
  title?: string
  sku?: string
  priceDelta?: number
  stock?: number
}

type ProductLike = {
  id?: string
  title?: string
  description?: string
  price?: number
  stock?: number
  active?: boolean
  variants?: VariantLike[]
  images?: string[]
}

export default function ProductDetail({ id }: { id: string }) {
  const [form, setForm] = useState<ProductLike | null>(null)
  const [busy, setBusy] = useState(false)
  const tabs: Array<'main'|'variants'|'media'|'relations'> = ['main','variants','media','relations']
  const [tab, setTab] = useState<typeof tabs[number]>('main')

  // Hent produkt
  useEffect(() => {
    let abort = false
    ;(async () => {
      try {
        const res = await fetch(`/api/products/${id}`, { cache: 'no-store' })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const data = await res.json()
        if (!abort) setForm(data ?? null)
      } catch (err) {
        console.error(err)
        if (!abort) setForm(null)
      }
    })()
    return () => { abort = true }
  }, [id])

  // Lagre
  const save = async () => {
    if (!form) return
    try {
      setBusy(true)
      const res = await fetch(`/api/products/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })
      if (res.ok) {
        ;(window as any).lbToast?.('Product saved')
      } else {
        ;(window as any).lbToast?.('Save failed')
      }
    } catch (e) {
      console.error(e)
      ;(window as any).lbToast?.('Save failed')
    } finally {
      setBusy(false)
    }
  }

  const update = (patch: Partial<ProductLike>) =>
    setForm(prev => ({ ...(prev ?? {} as ProductLike), ...patch }))

  const updateVariant = (ix: number, patch: Partial<VariantLike>) =>
    setForm(prev => {
      const p = (prev ?? {} as ProductLike)
      const arr = [...(p.variants ?? [])]
      arr[ix] = { ...(arr[ix] ?? {}), ...patch }
      return { ...p, variants: arr }
    })

  const addVariant = () =>
    setForm(prev => {
      const p = (prev ?? {} as ProductLike)
      const arr = [...(p.variants ?? [])]
      arr.push({ title: `Variant ${arr.length + 1}`, sku: '', priceDelta: 0, stock: 0 })
      return { ...p, variants: arr }
    })

  const removeVariant = (ix: number) =>
    setForm(prev => {
      const p = (prev ?? {} as ProductLike)
      const arr = [...(p.variants ?? [])]
      arr.splice(ix, 1)
      return { ...p, variants: arr }
    })

  return (
    <AdminFrame>
      <div className="flex items-center justify-between gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-semibold">
            {form ? (form.title || `Product ${id}`) : `Product ${id}`}
          </h1>
          <p className="text-sm text-neutral-500">ID: {id}</p>
        </div>
        <button
          onClick={save}
          disabled={busy || !form}
          className="px-4 py-2 rounded bg-black text-white disabled:opacity-50"
        >
          {busy ? 'Saving…' : 'Save'}
        </button>
      </div>

      {/* Tab-bar uavhengig av AdminPage */}
      <div className="border-b mb-4">
        <nav className="-mb-px flex gap-4">
          {tabs.map(t => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`px-3 py-2 border-b-2 ${tab === t ? 'border-black font-medium' : 'border-transparent text-neutral-500 hover:text-black'}`}
            >
              {t[0].toUpperCase() + t.slice(1)}
            </button>
          ))}
        </nav>
      </div>

      {!form ? (
        <div className="p-6">Loading…</div>
      ) : (
        <div className="space-y-8">
          {/* MAIN */}
          {tab === 'main' && (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium mb-1">Title</label>
                  <input
                    className="w-full rounded border px-3 py-2"
                    value={form.title ?? ''}
                    onChange={(e) => update({ title: e.target.value })}
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-1">Description</label>
                  <textarea
                    className="w-full rounded border px-3 py-2 min-h-[120px]"
                    value={form.description ?? ''}
                    onChange={(e) => update({ description: e.target.value })}
                  />
                </div>
              </div>

              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium mb-1">Price</label>
                  <input
                    type="number"
                    className="w-full rounded border px-3 py-2"
                    value={form.price ?? 0}
                    onChange={(e) => update({ price: Number(e.target.value) })}
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-1">Stock</label>
                  <input
                    type="number"
                    className="w-full rounded border px-3 py-2"
                    value={form.stock ?? 0}
                    onChange={(e) => update({ stock: Number(e.target.value) })}
                  />
                </div>
                <label className="inline-flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={!!form.active}
                    onChange={(e) => update({ active: e.target.checked })}
                  />
                  <span>Active</span>
                </label>
              </div>
            </div>
          )}

          {/* VARIANTS */}
          {tab === 'variants' && (
            <div className="space-y-4">
              {BulkVariantEdit ? (
                // Hvis du har en full BulkVariantEdit-komponent
                <BulkVariantEdit product={form} onChange={(p: ProductLike) => setForm(p)} />
              ) : (
                <>
                  <div className="flex justify-between items-center">
                    <h2 className="text-lg font-medium">Variants</h2>
                    <button
                      onClick={addVariant}
                      className="px-3 py-2 rounded border"
                    >
                      Add variant
                    </button>
                  </div>
                  <div className="overflow-x-auto">
                    <table className="min-w-full border rounded">
                      <thead className="bg-neutral-50">
                        <tr>
                          <th className="text-left px-3 py-2 border-b">Title</th>
                          <th className="text-left px-3 py-2 border-b">SKU</th>
                          <th className="text-left px-3 py-2 border-b">Price Δ</th>
                          <th className="text-left px-3 py-2 border-b">Stock</th>
                          <th className="px-3 py-2 border-b"></th>
                        </tr>
                      </thead>
                      <tbody>
                        {(form.variants ?? []).map((v, ix) => (
                          <tr key={ix} className="border-b">
                            <td className="px-3 py-2">
                              <input
                                className="w-full rounded border px-2 py-1"
                                value={v.title ?? ''}
                                onChange={(e) => updateVariant(ix, { title: e.target.value })}
                              />
                            </td>
                            <td className="px-3 py-2">
                              <input
                                className="w-full rounded border px-2 py-1"
                                value={v.sku ?? ''}
                                onChange={(e) => updateVariant(ix, { sku: e.target.value })}
                              />
                            </td>
                            <td className="px-3 py-2">
                              <input
                                type="number"
                                className="w-full rounded border px-2 py-1"
                                value={v.priceDelta ?? 0}
                                onChange={(e) => updateVariant(ix, { priceDelta: Number(e.target.value) })}
                              />
                            </td>
                            <td className="px-3 py-2">
                              <input
                                type="number"
                                className="w-full rounded border px-2 py-1"
                                value={v.stock ?? 0}
                                onChange={(e) => updateVariant(ix, { stock: Number(e.target.value) })}
                              />
                            </td>
                            <td className="px-3 py-2 text-right">
                              <button
                                onClick={() => removeVariant(ix)}
                                className="px-2 py-1 rounded border text-red-600"
                              >
                                Remove
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </>
              )}
            </div>
          )}

          {/* MEDIA */}
          {tab === 'media' && (
            <div className="space-y-4">
              {VariantImages ? (
                <VariantImages product={form} onChange={(p: ProductLike) => setForm(p)} />
              ) : (
                <div className="rounded border p-6 text-neutral-600">
                  Media manager (VariantImages) ikke funnet – viser placeholder.
                </div>
              )}
            </div>
          )}

          {/* RELATIONS */}
          {tab === 'relations' && (
            <div className="rounded border p-6 text-neutral-600">
              Relations coming soon…
            </div>
          )}
        </div>
      )}
    </AdminFrame>
  )
}
TSX

echo "→ Rydder .next cache…"
rm -rf .next

echo "✓ Ferdig! Start dev-server på nytt: npm run dev (og hard-reload i nettleser)."
