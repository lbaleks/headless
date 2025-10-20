'use client';

import React from 'react';
import Link from 'next/link';
import { AdminPage } from '@/components/AdminPage';

type Order = {
  id: string;
  number?: string;
  status?: string;
  total?: number;
  customerName?: string;
  createdAt?: string;
};

function coerceNumber(n: any): number | undefined {
  if (n == null) return undefined;
  if (typeof n === 'number') return n;
  if (typeof n === 'string') {
    const x = Number(n.replace?.(/[^\d.,-]/g, '').replace(',', '.') ?? n);
    return Number.isFinite(x) ? x : undefined;
  }
  return undefined;
}
const pick = <T = any,>(obj: any, path: string): T | undefined =>
  path.split('.').reduce<any>((acc, key) => (acc == null ? undefined : acc[key]), obj);

function normalizeOrder(raw: any): Order | null {
  if (!raw) return null;
  const id = raw.id ?? raw._id ?? raw.orderId ?? raw.uuid ?? raw.number ?? raw.no;
  if (!id) return null;
  const number = raw.number ?? raw.no ?? String(id);
  const status = raw.status ?? raw.state ?? raw.orderStatus ?? raw.paymentStatus;
  const total =
    coerceNumber(raw.total) ??
    coerceNumber(raw.totalPrice) ??
    coerceNumber(raw.grand_total) ??
    coerceNumber(raw.amount) ??
    coerceNumber(raw.summary?.total);
  const customerName =
    pick<string>(raw, 'customer.name') ??
    pick<string>(raw, 'customer.fullName') ??
    (pick<string>(raw, 'customer.firstName') && pick<string>(raw, 'customer.lastName')
      ? `${pick<string>(raw, 'customer.firstName')} ${pick<string>(raw, 'customer.lastName')}`.trim()
      : undefined) ??
    raw.customerName ?? raw.clientName ?? raw.userName ?? undefined;
  const createdAt =
    raw.createdAt ?? raw.created_at ?? raw.date ?? raw.placedAt ?? raw.created ??
    (raw.meta && (raw.meta.createdAt || raw.meta.created_at));

  return { id: String(id), number: String(number), status, total, customerName, createdAt };
}

// Tar høyde for arrays, nestede arrays, edges, og objekter med id=>order
function extractOrders(data: any): any[] {
  console.debug('[ORDERS] raw json:', JSON.parse(JSON.stringify(data)));

  // Klassiske steder
  const candidates: any[] = [];
  if (Array.isArray(data)) candidates.push(data);
  if (Array.isArray(data?.items)) candidates.push(data.items);
  if (Array.isArray(data?.data?.items)) candidates.push(data.data.items);
  if (Array.isArray(data?.orders)) candidates.push(data.orders);
  if (Array.isArray(data?.data?.orders)) candidates.push(data.data.orders);
  if (Array.isArray(data?.results)) candidates.push(data.results);
  if (Array.isArray(data?.data?.results)) candidates.push(data.data.results);
  if (Array.isArray(data?.edges)) candidates.push(data.edges.map((e:any)=>e?.node ?? e));
  if (Array.isArray(data?.data?.edges)) candidates.push(data.data.edges.map((e:any)=>e?.node ?? e));
  if (Array.isArray(data?.list)) candidates.push(data.list);

  for (const c of candidates) if (Array.isArray(c)) return c;

  // Håndter objekter med id-nøkler: { "123": {...}, "124": {...} }
  if (data && typeof data === 'object' && !Array.isArray(data)) {
    const vals = Object.values(data);
    if (vals.every(v => v && typeof v === 'object')) return vals as any[];
  }

  return [];
}

async function fetchOrders(): Promise<Order[]> {
  const endpoints = ['/api/orders?page=1&size=9999','/api/orders'];
  let lastErr: any;
  for (const url of endpoints) {
    try {
      console.debug('[ORDERS] fetching', url);
      const res = await fetch(url, { cache: 'no-store' });
      console.debug('[ORDERS] status', url, res.status);
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const json = await res.json();
      const rows = extractOrders(json).map(normalizeOrder).filter(Boolean) as Order[];
      console.debug('[ORDERS] parsed rows', rows.length, rows[0]);
      return rows;
    } catch (e) {
      lastErr = e;
      console.warn('[ORDERS] fetch failed', url, e);
    }
  }
  throw lastErr ?? new Error('Kunne ikke hente ordrer');
}

export default function OrdersList() {
  const [orders, setOrders] = React.useState<Order[] | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    let abort = false;
    (async () => {
      try {
        console.debug('[ORDERS] effect start');
        const items = await fetchOrders();
        if (!abort) setOrders(items);
      } catch (e: any) {
        if (!abort) setError(e?.message ?? 'Kunne ikke laste ordrer');
      }
    })();
    return () => { abort = true; };
  }, []);

  return (
    <AdminPage title="Orders">
      <div className="p-4">
        {!orders && !error && <div>Loading…</div>}
        {error && <div className="text-red-600 text-sm">{error}</div>}
        {orders && orders.length === 0 && (
          <div className="text-sm text-neutral-500">
            Ingen ordrer funnet. Se console for <code>[ORDERS]</code>-logger.
          </div>
        )}
        {orders && orders.length > 0 && (
          <div className="overflow-auto rounded border">
            <table className="min-w-[720px] w-full text-sm">
              <thead>
                <tr className="bg-neutral-50 text-neutral-600">
                  <th className="text-left p-2">Order</th>
                  <th className="text-left p-2">Kunde</th>
                  <th className="text-left p-2">Status</th>
                  <th className="text-right p-2">Total</th>
                  <th className="text-left p-2">Opprettet</th>
                </tr>
              </thead>
              <tbody>
                {orders.map((o) => (
                  <tr key={o.id} className="border-t hover:bg-neutral-50">
                    <td className="p-2">
                      <Link href={`/admin/orders/${o.id}`} className="underline">
                        {o.number ?? o.id}
                      </Link>
                    </td>
                    <td className="p-2">{o.customerName ?? '—'}</td>
                    <td className="p-2">{o.status ?? '—'}</td>
                    <td className="p-2 text-right">
                      {typeof o.total === 'number' ? o.total.toFixed(2) : '—'}
                    </td>
                    <td className="p-2">
                      {o.createdAt ? new Date(o.createdAt).toLocaleString() : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </AdminPage>
  );
}