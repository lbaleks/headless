"use client";



import BulkEditDialog, { BulkEditDialog as _BulkEditDialogNamed } from "@/components/BulkEditDialog";
import { AdminPage } from "@/components/AdminPage";
import Link from 'next/link';
import React, { useEffect, useState } from 'react';
type Product = {
  id?: string
  _id?: string
  name?: string
  sku?: string
  stock?: number
}

async function getJSON<T>(url: string): Promise<{data?: T, error?: string}> {
  try {
    const res = await fetch(url, { cache: 'no-store' }, { cache: 'no-store' })
    if (!res.ok) return { error: `HTTP ${res.status}` }
    const raw = await res.json()
    // Tillat ulike API-formater: array direkte, {items}, {data}
    const arr = Array.isArray(raw) ? raw : (raw?.items ?? raw?.data ?? [])
    return { data: arr as T }
  } catch (e:any) {
    return { error: e?.message || 'Ukjent feil' }
  }
}

export default function ProductsPage(){
  async function clearOverride(sku: string) {
    await fetch(`/api/products/${encodeURIComponent(sku, { cache: 'no-store' , cache: 'no-store'})}`, { method: 'DELETE' })
    if (typeof window !== 'undefined') {
      // enkel refresh hvis SWR ikke er i bruk
      try { (window as any).location?.reload() } catch {}
    }
  }

  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | undefined>()
  const [rows, setRows] = useState<Product[]>([])
  const [q, setQ] = useState('')

  useEffect(() => {
    let mounted = true
    const run = async () => {
      setBusy(true)
      setError(undefined)
      const { data, error } = await getJSON<Product[]>('/api/products?page=1&size=200')
      if (!mounted) return
      if (error) setError(error)
      setRows(Array.isArray(data) ? data : [])
      setBusy(false)
    }
    const watchdog = setTimeout(() => mounted && setBusy(false), 20000)
    run()
    return () => { mounted = false;
clearTimeout(watchdog) }
  }, [])

  const filtered = React.useMemo(() => {
    const term = q.trim().toLowerCase()
    if (!term) return rows
    return rows.filter(p =>
      (p.name||'').toLowerCase().includes(term) ||
      (p.sku||'').toLowerCase().includes(term) ||
      String(p.id||p._id||'').toLowerCase().includes(term)
    )
  }, [rows, q])

  return (
    <AdminPage title="Products">
      <div className="p-4 flex items-center gap-2">
        <input
          value={q}
          onChange={e=>setQ(e.target.value)}
          placeholder="Søk på navn / SKU / ID…"
          className="w-full md:w-96 px-3 py-2 rounded border outline-none focus:ring"
        />
        <div className="text-xs text-neutral-500">{filtered.length} / {rows.length}</div>
      </div>

      {busy && <div className="p-6 text-sm text-neutral-500">Loading…</div>}
      {!busy && error && (
        <div className="p-6 text-sm text-red-600">Kunne ikke laste: {error}</div>
      )}
      {!busy && !error && filtered.length === 0 && (
        <div className="p-6 text-sm text-neutral-500">Ingen produkter funnet.</div>
      )}

      {!busy && !error && filtered.length > 0 && (
        <div className="p-4">
          <div className="overflow-auto border rounded">
<BulkEditDialog />

            <table className="min-w-full text-sm">
              <thead className="bg-neutral-50 text-neutral-600">
                <tr>
                  <th className="text-left p-2">ID</th>
                  <th className="text-left p-2">Name</th>
                  <th className="text-left p-2">SKU</th>
                  <th className="text-left p-2">Stock</th>
                  <th className="text-left p-2">Complete</th>
  <th className="text-left p-2">IBU</th>
  <th className="text-left p-2">Humle</th>
</tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map((p, i) => (
                  <tr key={(p.id as string) || (p._id as string) || String(i)} className="hover:bg-neutral-50">
                    <td className="p-2">{p.id || p._id || '-'}</td>
                    <td className="p-2">{p.name || '-'}</td>
                    <td className="p-2">{p.sku || '-'}</td>
                    <td className="p-2">{p.stock ?? '-'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </AdminPage>
  )
}
