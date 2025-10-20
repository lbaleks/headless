'use client';
import React from 'react'
import { AdminPage } from '@/components/AdminPage'
import { safeFetchJSON } from '@/lib/safe-fetch'

type OrderLine = { sku?: string; name?: string; qty?: number }
type Order = {
  id?: string
  _id?: string
  orderId?: string
  createdAt?: string | number
  date?: string | number
  customer?: { name?: string; email?: string }
  lines?: OrderLine[]
}

export default function OrdersPage(){
  const [busy, setBusy] = React.useState(true)
  const [error, setError] = React.useState<string | undefined>(undefined)
  const [rows, setRows] = React.useState<Order[]>([])

  React.useEffect(() => {
    let mounted = true
    const run = async () => {
      setBusy(true)
      setError(undefined)
      const { data, error } = await safeFetchJSON<Order[]>('/api/orders')
      if (!mounted) return
      if (error) setError(error)
      setRows(Array.isArray(data) ? data : [])
      setBusy(false)
    }
    const watchdog = setTimeout(() => mounted && setBusy(false), 20000)
    run()
    return () => { mounted = false; clearTimeout(watchdog) }
  }, [])

  return (
    <AdminPage title="Orders">
      {busy && <div className="p-6 text-sm text-neutral-500">Loading…</div>}
      {!busy && error && (
        <div className="p-6 text-sm text-red-600">Kunne ikke laste: {error}</div>
      )}
      {!busy && !error && rows.length === 0 && (
        <div className="p-6 text-sm text-neutral-500">Ingen ordre funnet.</div>
      )}
      {!busy && !error && rows.length > 0 && (
        <div className="p-4">
          <div className="overflow-auto border rounded">
            <table className="min-w-full text-sm">
              <thead className="bg-neutral-50 text-neutral-600">
                <tr>
                  <th className="text-left p-2">Order ID</th>
                  <th className="text-left p-2">Date</th>
                  <th className="text-left p-2">Customer</th>
                  <th className="text-left p-2">Lines</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((r, i) => (
                  <tr key={(r.id as string) || (r._id as string) || String(i)} className="hover:bg-neutral-50">
                    <td className="p-2">{r.orderId || r.id || r._id || '-'}</td>
                    <td className="p-2">
                      {(() => {
                        const d = r.createdAt ?? r.date
                        if (!d) return '-'
                        try { return new Date(d as any).toLocaleString() } catch { return String(d) }
                      })()}
                    </td>
                    <td className="p-2">{r.customer?.name || r.customer?.email || '-'}</td>
                    <td className="p-2">{Array.isArray(r.lines) ? r.lines.length : 0}</td>
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
