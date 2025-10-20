'use client';
import React from 'react'
import Link from 'next/link'
import { AdminPage } from '@/components/AdminPage'

type Customer = {
  id?: string
  _id?: string
  name?: string
  email?: string
  phone?: string
}

function cid(c: any) { return c?.id || c?._id || '' }

function normalizeCustomers(raw: any): Customer[] {
  const arr = Array.isArray(raw) ? raw : (raw?.items ?? raw?.data ?? [])
  return (arr || []).map((c: any) => ({
    id: c?.id ?? c?._id,
    _id: c?._id,
    name: c?.name ?? c?.fullName ?? 'Ukjent',
    email: c?.email ?? c?.mail ?? '',
    phone: c?.phone ?? c?.tel ?? ''
  }))
}

async function fetchCustomers(q: string) {
  const params = new URLSearchParams()
  params.set('page', '1')
  params.set('size', '200')
  if (q.trim()) params.set('q', q.trim())
  const res = await fetch(`/api/customers?${params.toString()}`, { cache: 'no-store' })
  if (!res.ok) return []
  const json = await res.json()
  return normalizeCustomers(json)
}

export default function CustomersPage(){
  const [q, setQ] = React.useState('')
  const [loading, setLoading] = React.useState(false)
  const [rows, setRows] = React.useState<Customer[]>([])

  // første last + debounce på søk
  React.useEffect(() => {
    let alive = true
    const t = setTimeout(async () => {
      setLoading(true)
      try {
        const list = await fetchCustomers(q)
        if (!alive) return
        setRows(list)
      } catch {
        if (!alive) return
        setRows([])
      } finally {
        if (alive) setLoading(false)
      }
    }, 250)
    return () => { alive = false; clearTimeout(t) }
  }, [q])

  return (
    <AdminPage title="Customers">
      <div className="p-4 space-y-4">
        <div className="flex items-center gap-2">
          <input
            className="w-full border rounded px-3 py-2"
            placeholder="Søk kunder (navn/e-post/telefon)…"
            value={q}
            onChange={e=>setQ(e.target.value)}
          />
        </div>

        <div className="border rounded overflow-hidden">
          <table className="min-w-full text-sm">
            <thead className="bg-neutral-50 text-neutral-600">
              <tr>
                <th className="text-left p-2">ID</th>
                <th className="text-left p-2">Name</th>
                <th className="text-left p-2">Email</th>
                <th className="text-left p-2">Phone</th>
                <th className="text-left p-2"></th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {loading && (
                <tr><td className="p-3 text-neutral-500" colSpan={5}>Laster…</td></tr>
              )}
              {!loading && rows.length === 0 && (
                <tr><td className="p-3 text-neutral-500" colSpan={5}>Ingen kunder funnet</td></tr>
              )}
              {!loading && rows.map((c, i) => {
                const id = cid(c)
                return (
                  <tr key={`${c.id ?? c.email ?? String(i)}-${i}`} className="hover:bg-neutral-50">
                    <td className="p-2">{id || '–'}</td>
                    <td className="p-2">{c.name || '–'}</td>
                    <td className="p-2">{c.email || '–'}</td>
                    <td className="p-2">{c.phone || '–'}</td>
                    <td className="p-2">
                      {id ? (
                        <Link
                          className="text-xs underline text-neutral-700 hover:text-black"
                          href={`/admin/customers/${id}`}
                        >Åpne</Link>
                      ) : null}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </div>
    </AdminPage>
  )
}
