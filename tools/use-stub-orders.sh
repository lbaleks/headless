#!/usr/bin/env bash
set -euo pipefail

echo "→ Setter ORDERS_MODE=stub i .env.local"
touch .env.local
grep -q '^ORDERS_MODE=' .env.local 2>/dev/null \
  && sed -i.bak 's/^ORDERS_MODE=.*/ORDERS_MODE=stub/' .env.local \
  || echo "ORDERS_MODE=stub" >> .env.local

echo "→ Initierer var/orders.dev.json"
mkdir -p var
[ -f var/orders.dev.json ] || echo '{"items":[]}' > var/orders.dev.json

echo "→ Skriver app/api/orders/route.ts (filbasert stub)"
cat > app/api/orders/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

const MODE = process.env.ORDERS_MODE || 'stub'
const STORE = path.join(process.cwd(), 'var', 'orders.dev.json')

type LineIn = { sku: string; qty?: number; price?: number; name?: string; productId?: number | string | null }
type CustomerIn = Record<string, any>
type OrderOut = {
  id: string
  increment_id: string
  status: string
  created_at: string
  customer: CustomerIn
  lines: Array<{
    sku: string
    productId: number | string | null
    name: string
    qty: number
    price: number
    rowTotal: number
    i: number
  }>
  notes: string
  total: number
  source: 'local-stub'
}

async function readStore(): Promise<{ items: OrderOut[] }> {
  try {
    const raw = await fs.readFile(STORE, 'utf8')
    return JSON.parse(raw)
  } catch {
    return { items: [] }
  }
}

async function writeStore(data: { items: OrderOut[] }) {
  await fs.mkdir(path.dirname(STORE), { recursive: true })
  await fs.writeFile(STORE, JSON.stringify(data, null, 2), 'utf8')
}

export async function GET(req: Request) {
  // Dev stub → les fra fil
  if (MODE === 'stub') {
    const url = new URL(req.url)
    const page = Math.max(1, Number(url.searchParams.get('page') ?? '1'))
    const size = Math.max(1, Number(url.searchParams.get('size') ?? '25'))
    const { items } = await readStore()
    const start = (page - 1) * size
    const slice = items
      .slice()
      .sort((a, b) => b.created_at.localeCompare(a.created_at))
      .slice(start, start + size)
    return NextResponse.json({ total: items.length, items: slice })
  }

  // Magento-modus → (kan fylles på senere). Myk-feil i dev:
  return NextResponse.json({ total: 0, items: [] })
}

export async function POST(req: Request) {
  if (MODE !== 'stub') {
    return NextResponse.json({ ok: false, error: 'Not implemented in magento mode (dev)' }, { status: 501 })
  }
  const body = (await req.json().catch(() => ({}))) as {
    customer?: CustomerIn
    lines?: LineIn[]
    notes?: string
  }

  const id = `ORD-${Date.now()}`
  const lines = Array.isArray(body.lines)
    ? body.lines.map((l: LineIn, i: number) => {
        const qty = Number(l.qty ?? 1)
        const price = Number(l.price ?? 0)
        return {
          sku: String(l.sku || 'UNKNOWN'),
          productId: l.productId ?? null,
          name: l.name ?? l.sku ?? 'Linje',
          qty,
          price,
          rowTotal: qty * price,
          i,
        }
      })
    : []

  const total = lines.reduce((s, it) => s + (Number(it.rowTotal) || 0), 0)

  const out: OrderOut = {
    id,
    increment_id: id,
    status: 'new',
    created_at: new Date().toISOString(),
    customer: body.customer ?? {},
    lines,
    notes: body.notes ?? '',
    total,
    source: 'local-stub',
  }

  const store = await readStore()
  store.items.push(out)
  await writeStore(store)

  return NextResponse.json(out, { status: 201 })
}

// Valgfritt: enkel PATCH for å oppdatere status/notes
export async function PATCH(req: Request) {
  if (MODE !== 'stub') {
    return NextResponse.json({ ok: false, error: 'Not implemented in magento mode (dev)' }, { status: 501 })
  }
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ ok: false, error: 'Missing id' }, { status: 400 })

  const patch = await req.json().catch(() => ({})) as Partial<Pick<OrderOut,'status'|'notes'>>
  const store = await readStore()
  const idx = store.items.findIndex(o => o.id === id || o.increment_id === id)
  if (idx < 0) return NextResponse.json({ ok: false, error: 'Not found' }, { status: 404 })

  store.items[idx] = { ...store.items[idx], ...patch }
  await writeStore(store)
  return NextResponse.json(store.items[idx])
}
TS

echo "→ Rydder .next-cache"
rm -rf .next .next-cache 2>/dev/null || true
echo "✓ Ferdig. Start dev på nytt: npm run dev"
