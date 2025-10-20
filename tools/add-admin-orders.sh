#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

say() { printf "%s\n" "$*"; }
step() { echo "→ $*"; }
ok() { echo "✓ $*"; }

step "Oppretter mapper…"
mkdir -p "$ROOT/app/admin/orders"
mkdir -p "$ROOT/app/admin/orders/[id]"

# Orders list – client component
step "Skriver app/admin/orders/OrdersList.client.tsx"
cat > "$ROOT/app/admin/orders/OrdersList.client.tsx" <<'TS'
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

export default function OrdersList() {
  const [orders, setOrders] = React.useState<Order[] | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    let abort = false;
    (async () => {
      try {
        const res = await fetch('/api/orders?page=1&size=9999', { cache: 'no-store' });
        if (!res.ok) throw new Error('HTTP ' + res.status);
        const data = await res.json();
        // Forsøk å lese enten {items: []} eller [] direkte
        const items: Order[] = Array.isArray(data) ? data : (data?.items ?? []);
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
          <div className="text-sm text-neutral-500">Ingen ordrer funnet.</div>
        )}

        {orders && orders.length > 0 && (
          <div className="overflow-auto rounded border">
            <table className="min-w-[720px] w-full text-sm">
              <thead>
                <tr className="bg-neutral-50 text-neutral-600">
                  <th className="text-left p-2">Order</th>
                  <th className="text-left p-2">Kunde</th>
                  <th className="text-left p-2">Status</th>
                  <th className="text-left p-2">Total</th>
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
                    <td className="p-2">{typeof o.total === 'number' ? o.total.toFixed(2) : '—'}</td>
                    <td className="p-2">{o.createdAt ? new Date(o.createdAt).toLocaleString() : '—'}</td>
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

# Orders list – page wrapper (server)
step "Skriver app/admin/orders/page.tsx"
cat > "$ROOT/app/admin/orders/page.tsx" <<'TS'
import OrdersList from './OrdersList.client';

export default function Page() {
  // Enkel server-wrapper -> klientkomponent gjør fetching
  return <OrdersList />;
}
TS

# Order detail – client component
step "Skriver app/admin/orders/[id]/OrderDetail.client.tsx"
cat > "$ROOT/app/admin/orders/[id]/OrderDetail.client.tsx" <<'TS'
'use client';

import React from 'react';
import Link from 'next/link';
import { AdminPage } from '@/src/components/AdminPage';

type OrderLine = {
  sku?: string;
  title?: string;
  qty?: number;
  price?: number;
  total?: number;
};

type Order = {
  id: string;
  number?: string;
  status?: string;
  total?: number;
  customerName?: string;
  customerEmail?: string;
  createdAt?: string;
  lines?: OrderLine[];
  meta?: Record<string, any>;
};

export default function OrderDetail({ id }: { id: string }) {
  const [order, setOrder] = React.useState<Order | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    let abort = false;
    (async () => {
      try {
        const res = await fetch(`/api/orders/${id}`, { cache: 'no-store' });
        if (!res.ok) throw new Error('HTTP ' + res.status);
        const data = await res.json();
        if (!abort) setOrder(data ?? null);
      } catch (e: any) {
        if (!abort) setError(e?.message ?? 'Kunne ikke laste ordre');
      }
    })();
    return () => { abort = true; };
  }, [id]);

  return (
    <AdminPage
      title={order ? `Order ${order.number ?? order.id}` : 'Order'}
      actions={<Link href="/admin/orders" className="text-sm underline">← Tilbake</Link>}
    >
      <div className="p-4 space-y-4">
        {!order && !error && <div>Loading…</div>}
        {error && <div className="text-red-600 text-sm">{error}</div>}

        {order && (
          <>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="rounded border p-3">
                <div className="font-medium mb-2">Grunnlag</div>
                <div className="text-sm">
                  <div><span className="text-neutral-500">ID:</span> {order.id}</div>
                  <div><span className="text-neutral-500">Nummer:</span> {order.number ?? '—'}</div>
                  <div><span className="text-neutral-500">Status:</span> {order.status ?? '—'}</div>
                  <div><span className="text-neutral-500">Opprettet:</span> {order.createdAt ? new Date(order.createdAt).toLocaleString() : '—'}</div>
                </div>
              </div>

              <div className="rounded border p-3">
                <div className="font-medium mb-2">Kunde</div>
                <div className="text-sm">
                  <div><span className="text-neutral-500">Navn:</span> {order.customerName ?? '—'}</div>
                  <div><span className="text-neutral-500">E-post:</span> {order.customerEmail ?? '—'}</div>
                </div>
              </div>

              <div className="rounded border p-3">
                <div className="font-medium mb-2">Betaling</div>
                <div className="text-sm">
                  <div><span className="text-neutral-500">Total:</span> {typeof order.total === 'number' ? order.total.toFixed(2) : '—'}</div>
                </div>
              </div>
            </div>

            <div className="rounded border">
              <div className="p-3 font-medium">Linjer</div>
              <div className="overflow-auto">
                <table className="min-w-[720px] w-full text-sm">
                  <thead>
                    <tr className="bg-neutral-50 text-neutral-600">
                      <th className="text-left p-2">SKU</th>
                      <th className="text-left p-2">Vare</th>
                      <th className="text-right p-2">Antall</th>
                      <th className="text-right p-2">Pris</th>
                      <th className="text-right p-2">Linjetotal</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(order.lines ?? []).map((l, ix) => (
                      <tr key={ix} className="border-t">
                        <td className="p-2">{l.sku ?? '—'}</td>
                        <td className="p-2">{l.title ?? '—'}</td>
                        <td className="p-2 text-right">{typeof l.qty === 'number' ? l.qty : '—'}</td>
                        <td className="p-2 text-right">{typeof l.price === 'number' ? l.price.toFixed(2) : '—'}</td>
                        <td className="p-2 text-right">{typeof l.total === 'number' ? l.total.toFixed(2) : '—'}</td>
                      </tr>
                    ))}
                    {(order.lines ?? []).length === 0 && (
                      <tr className="border-t">
                        <td className="p-2 text-neutral-500" colSpan={5}>Ingen linjer</td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        )}
      </div>
    </AdminPage>
  );
}
TS

# Order detail – page wrapper (server + React.use on params)
step "Skriver app/admin/orders/[id]/page.tsx"
cat > "$ROOT/app/admin/orders/[id]/page.tsx" <<'TS'
import React from 'react';
import OrderDetail from './OrderDetail.client';

export default function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  return <OrderDetail id={id} />;
}
TS

# Rydd litt cache
if [ -d "$ROOT/.next" ]; then
  step "Rydder .next-cache"
  rm -rf "$ROOT/.next"
fi

ok "Ferdig. Start dev-server på nytt (npm run dev / yarn dev / pnpm dev)."


chmod +x "$ROOT/tools/add-admin-orders.sh"
ok "Skript gjort kjørbart."