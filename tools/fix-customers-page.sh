#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
OUT="$ROOT/app/admin/customers/page.tsx"

echo "→ Skriver $OUT"
mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<'TSX'
'use client'
import React from 'react'
import { AdminPage } from '@/src/components/AdminPage'

type Customer = {
  id?: string
  _id?: string
  name?: string
  email?: string
  phone?: string
}

async function getJSON<T>(url: string): Promise<{data?: T, error?: string}> {
  try {
    const res = await fetch(url, { cache: 'no-store' })
    if (!res.ok) return { error: `HTTP ${res.status}` }
    const raw = await res.json()
    // Støtt array direkte, {items}, {data}
    const arr = Array.isArray(raw) ? raw : (raw?.items ?? raw?.data ?? [])
    return { data: arr as T }
  } catch (e:any) {
    return { error: e?.message || 'Ukjent feil' }
  }
}

export default function CustomersPage(){
  const [busy, setBusy] = React.useState(true)
  const [error, setError] = React.useState<string | undefined>()
  const [rows, setRows] = React.useState<Customer[]>([])
  const [q, setQ] = React.useState('')

  React.useEffect(() => {
    let mounted = true
    const run = async () => {
      setBusy(true)
      setError(undefined)
      // Bytt endpoint her hvis ditt API er annerledes (f.eks. /api/admin/customers)
      const { data, error } = await getJSON<Customer[]>('/api/customers?page=1&size=200')
      if (!mounted) return
      if (error) setError(error)
      setRows(Array.isArray(data) ? data : [])
      setBusy(false)
    }
    const watchdog = setTimeout(() => mounted && setBusy(false), 20000)
    run()
    return () => { mounted = false; clearTimeout(watchdog) }
  }, [])

  const filtered = React.useMemo(() => {
    const term = q.trim().toLowerCase()
    if (!term) return rows
    return rows.filter(c =>
      (c.name||'').toLowerCase().includes(term) ||
      (c.email||'').toLowerCase().includes(term) ||
      (c.phone||'').toLowerCase().includes(term) ||
      String(c.id||c._id||'').toLowerCase().includes(term)
    )
  }, [rows, q])

  return (
    <AdminPage title="Customers">
      <div className="p-4 flex items-center gap-2">
        <input
          value={q}
          onChange={e=>setQ(e.target.value)}
          placeholder="Søk på navn / e-post / telefon / ID…"
          className="w-full md:w-96 px-3 py-2 rounded border outline-none focus:ring"
        />
        <div className="text-xs text-neutral-500">{filtered.length} / {rows.length}</div>
      </div>

      {busy && <div className="p-6 text-sm text-neutral-500">Loading…</div>}
      {!busy && error && (
        <div className="p-6 text-sm text-red-600">Kunne ikke laste: {error}</div>
      )}
      {!busy && !error && filtered.length === 0 && (
        <div className="p-6 text-sm text-neutral-500">Ingen kunder funnet.</div>
      )}

      {!busy && !error && filtered.length > 0 && (
        <div className="p-4">
          <div className="overflow-auto border rounded">
            <table className="min-w-full text-sm">
              <thead className="bg-neutral-50 text-neutral-600">
                <tr>
                  <th className="text-left p-2">ID</th>
                  <th className="text-left p-2">Name</th>
                  <th className="text-left p-2">Email</th>
                  <th className="text-left p-2">Phone</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map((c, i) => (
                  <tr key={(c.id as string) || (c._id as string) || String(i)} className="hover:bg-neutral-50">
                    <td className="p-2">{c.id || c._id || '-'}</td>
                    <td className="p-2">{c.name || '-'}</td>
                    <td className="p-2">{c.email || '-'}</td>
                    <td className="p-2">{c.phone || '-'}</td>
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
TSX

echo "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true
echo "✓ Ferdig. Start dev-server på nytt (npm run dev)."
