#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"

echo "→ Oppretter mapper…"
mkdir -p "$ROOT/src/lib"
mkdir -p "$ROOT/app/api/orders/[id]"
mkdir -p "$ROOT/data"

STORE="$ROOT/src/lib/orders-store.ts"
INDEX_ROUTE="$ROOT/app/api/orders/route.ts"
ID_ROUTE="$ROOT/app/api/orders/[id]/route.ts"

echo "→ Skriver $STORE"
cat > "$STORE" <<'TS'
import fs from 'fs'
import path from 'path'
import { randomUUID } from 'crypto'

export type OrderLine = {
  productId: string
  variantId?: string
  qty: number
  price?: number
  title?: string
}

export type Order = {
  id: string
  createdAt: string
  customer?: {
    id?: string
    email?: string
    name?: string
    phone?: string
  }
  lines: OrderLine[]
  notes?: string
}

const DATA_DIR = path.join(process.cwd(), 'data')
const FILE = path.join(DATA_DIR, 'orders.json')

function ensureFile() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true })
  if (!fs.existsSync(FILE)) fs.writeFileSync(FILE, '[]', 'utf8')
}

function readAll(): Order[] {
  ensureFile()
  const raw = fs.readFileSync(FILE, 'utf8')
  try {
    const arr = JSON.parse(raw)
    return Array.isArray(arr) ? arr : []
  } catch {
    return []
  }
}

function writeAll(orders: Order[]) {
  ensureFile()
  fs.writeFileSync(FILE, JSON.stringify(orders, null, 2), 'utf8')
}

export function listOrders(): Order[] {
  return readAll().sort((a,b)=> (a.createdAt<b.createdAt?1:-1))
}

export function getOrder(id: string): Order | undefined {
  return readAll().find(o => o.id === id)
}

export function createOrder(input: {
  customer?: Order['customer']
  lines: OrderLine[]
  notes?: string
}): Order {
  const order: Order = {
    id: randomUUID(),
    createdAt: new Date().toISOString(),
    customer: input.customer,
    lines: input.lines || [],
    notes: input.notes?.trim() || undefined
  }
  const all = readAll()
  all.push(order)
  writeAll(all)
  return order
}
TS

echo "→ Skriver $INDEX_ROUTE (liste/POST)"
cat > "$INDEX_ROUTE" <<'TS'
import { NextResponse } from 'next/server'
import { createOrder, listOrders, type OrderLine } from '@/src/lib/orders-store'

export async function GET() {
  try {
    const orders = listOrders()
    return NextResponse.json(orders, { status: 200 })
  } catch (e) {
    console.error(e)
    return NextResponse.json({ error: 'Failed to list orders' }, { status: 500 })
  }
}

export async function POST(req: Request) {
  try {
    const body = await req.json()

    // Minimal validering
    const lines: OrderLine[] = Array.isArray(body?.lines) ? body.lines.map((l:any)=>({
      productId: String(l.productId),
      variantId: l.variantId ? String(l.variantId) : undefined,
      qty: Number(l.qty)||1,
      price: (l.price===''||l.price==null) ? undefined : Number(l.price),
      title: l.title ? String(l.title) : undefined
    })) : []

    if (lines.length === 0) {
      return NextResponse.json({ error: 'Lines required' }, { status: 400 })
    }

    const order = createOrder({
      customer: body?.customer,
      lines,
      notes: body?.notes
    })

    return NextResponse.json(order, { status: 201 })
  } catch (e) {
    console.error(e)
    return NextResponse.json({ error: 'Failed to create order' }, { status: 500 })
  }
}
TS

echo "→ Skriver $ID_ROUTE (GET detalj)"
cat > "$ID_ROUTE" <<'TS'
import { NextResponse } from 'next/server'
import { getOrder } from '@/src/lib/orders-store'

export async function GET(
  _req: Request,
  ctx: { params: Promise<{ id: string }> }
) {
  const { id } = await ctx.params
  const order = getOrder(id)
  if (!order) {
    return NextResponse.json({ error: 'Not found' }, { status: 404 })
  }
  return NextResponse.json(order, { status: 200 })
}
TS

echo "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true

echo "✓ Ferdig. Start dev-server (npm run dev) og åpne ordren igjen."