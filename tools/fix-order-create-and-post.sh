#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"

echo "→ Oppretter apiCreateOrder i src/lib/orders.ts"
mkdir -p "$ROOT/src/lib"
cat > "$ROOT/src/lib/orders.ts" <<'TS'
export async function apiCreateOrder(args: { customer: any; lines: any[]; notes?: string }): Promise<any> {
  const { customer, lines, notes } = args || ({} as any)
  const res = await fetch('/api/orders', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ customer, lines, notes }),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return await res.json()
}
TS
echo "  ✓ src/lib/orders.ts skrevet"

ORD_CLIENT="$ROOT/app/admin/orders/new/OrderCreate.client.tsx"
if [ -f "$ORD_CLIENT" ]; then
  echo "→ Patcher $ORD_CLIENT"

  # Legg til import hvis den mangler
  if ! grep -q "apiCreateOrder" "$ORD_CLIENT" >/dev/null 2>&1; then
    echo "  → Legger til import { apiCreateOrder } fra '@/src/lib/orders'"
    TMP="$ORD_CLIENT.__tmp__"
    {
      echo "import { apiCreateOrder } from '@/src/lib/orders'"
      cat "$ORD_CLIENT"
    } > "$TMP"
    mv "$TMP" "$ORD_CLIENT"
  else
    echo "  → Import finnes allerede (hopper over)"
  fi

  # Erstatt ev. gamle kall createOrder( → apiCreateOrder(
  if grep -q "createOrder(" "$ORD_CLIENT" >/dev/null 2>&1; then
    echo "  → Erstatter createOrder( → apiCreateOrder("
    sed 's/\bcreateOrder(/apiCreateOrder(/g' "$ORD_CLIENT" > "$ORD_CLIENT.__new__"
    mv "$ORD_CLIENT.__new__" "$ORD_CLIENT"
  else
    echo "  → Fant ingen createOrder( å erstatte (ok)"
  fi
else
  echo "  ! Fant ikke $ORD_CLIENT – hopper over klientpatch"
fi

echo "→ Oppretter/patcher /api/orders/route.ts med POST"
ORD_ROUTE="$ROOT/app/api/orders/route.ts"
mkdir -p "$(dirname "$ORD_ROUTE")"

if [ ! -f "$ORD_ROUTE" ]; then
  echo "  → Lager ny route.ts (GET + POST, in-memory)"
  cat > "$ORD_ROUTE" <<'TS'
import { NextResponse } from 'next/server'

type Order = {
  id: string
  customer?: any
  lines: any[]
  notes?: string
  status: 'new' | 'paid' | 'cancelled'
  createdAt: string
  updatedAt: string
}

// enkel in-memory store pr. dev-prosess
const g = globalThis as any
if (!g.__ORDERS__) g.__ORDERS__ = [] as Order[]

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)
  const page = Number(searchParams.get('page') || 1)
  const size = Number(searchParams.get('size') || 50)
  const items: Order[] = g.__ORDERS__
  const start = (page - 1) * size
  const slice = items.slice(start, start + size)
  return NextResponse.json({ items: slice, total: items.length, page, size })
}

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}))
  const id =
    (crypto as any).randomUUID?.() ||
    Math.random().toString(36).slice(2)
  const now = new Date().toISOString()
  const order: Order = {
    id,
    customer: body.customer ?? null,
    lines: Array.isArray(body.lines) ? body.lines : [],
    notes: body.notes ?? '',
    status: 'new',
    createdAt: now,
    updatedAt: now,
  }
  order.lines = order.lines.map((l: any, ix: number) => ({ lineId: `${id}-${ix}`, ...l }))
  g.__ORDERS__.unshift(order)
  return NextResponse.json(order, { status: 201 })
}
TS
else
  # Fil finnes: sørg for NextResponse-import
  if ! grep -q "NextResponse" "$ORD_ROUTE" >/dev/null 2>&1; then
    echo "  → Legger til import { NextResponse }"
    TMP="$ORD_ROUTE.__tmp__"
    { echo "import { NextResponse } from 'next/server'"; cat "$ORD_ROUTE"; } > "$TMP"
    mv "$TMP" "$ORD_ROUTE"
  fi

  # Legg til in-memory store om mangler
  if ! grep -q "__ORDERS__" "$ORD_ROUTE" >/dev/null 2>&1; then
    echo "  → Legger til in-memory store"
    cat >> "$ORD_ROUTE" <<'TS'

const g = globalThis as any
if (!g.__ORDERS__) g.__ORDERS__ = []
TS
  fi

  # Legg til POST om mangler
  if ! grep -q "export async function POST" "$ORD_ROUTE" >/dev/null 2>&1; then
    echo "  → Legger til POST-handler"
    cat >> "$ORD_ROUTE" <<'TS'

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}))
  const id =
    (crypto as any).randomUUID?.() ||
    Math.random().toString(36).slice(2)
  const now = new Date().toISOString()
  const order = {
    id,
    customer: body.customer ?? null,
    lines: Array.isArray(body.lines) ? body.lines : [],
    notes: body.notes ?? '',
    status: 'new',
    createdAt: now,
    updatedAt: now,
  }
  order.lines = order.lines.map((l: any, ix: number) => ({ lineId: `${id}-${ix}`, ...l }))
  g.__ORDERS__.unshift(order)
  return NextResponse.json(order, { status: 201 })
}
TS
  else
    echo "  → POST finnes allerede (hopper over)"
  fi
fi

echo "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true

echo "✓ Ferdig. Start dev-server på nytt (npm run dev / yarn dev / pnpm dev)."