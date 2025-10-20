#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/app/admin/orders/OrdersList.client.tsx"

echo "→ Sjekker fil: $TARGET"
if [ ! -f "$TARGET" ]; then
  echo "Fant ikke $TARGET. Åpne /admin/orders en gang, eller lag filen manuelt."
  exit 1
fi

echo "→ Patcher OrdersList.client.tsx"
cat > "$TARGET" <<'TS'
'use client';

import React from 'react';
import Link from 'next/link';
import { AdminPage } from '@/src/components/AdminPage';

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

function pick<T=any>(obj: any, path: string): T | undefined {
  if (!obj) return undefined;
  return path.split('.').reduce<any>((acc, key) => (acc == null ? undefined : acc[key]), obj);
}

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

function extractOrders(data: any): any[] {
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
  return [];
}

async function fetchOrders(): Promise<Order[]> {
  const endpoints = ['/api/orders?page=1&size=9999','/api/orders'];
  let lastErr: any;
  for (const url of endpoints) {
    try {
      const res = await fetch(url, { cache: 'no-store' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const json = await res.json();
      const rows = extractOrders(json).map(normalizeOrder).filter(Boolean) as Order[];
      console.debug('[ORDERS_DEBUG]', { url, count: rows.length, sample: rows[0] });
      return rows;
    } catch (e) {
      lastErr = e;
      console.debug('[ORDERS_DEBUG_ERROR]', url, e);
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
            Ingen ordrer funnet. Sjekk nettverkskallet og konsollen for <code>[ORDERS_DEBUG]</code>.
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
TS

# rydder .next for sikkerhets skyld
if [ -d "$ROOT/.next" ]; then
  echo "→ Rydder .next-cache"
  rm -rf "$ROOT/.next"
fi

echo "✓ Ferdig. Start dev på nytt."
