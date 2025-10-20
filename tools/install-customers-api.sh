#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"

echo "→ Oppretter mapper…"
mkdir -p "$ROOT/src/lib" "$ROOT/app/api/customers" "$ROOT/public"

echo "→ Skriver src/lib/customers.ts"
cat > "$ROOT/src/lib/customers.ts" <<'TS'
export type Customer = {
  id: string
  name: string
  email?: string
  phone?: string
  createdAt?: string
}

type CustomerInput = Omit<Customer, 'id'|'createdAt'> & Partial<Pick<Customer,'id'|'createdAt'>>

declare global { // dev-hot reload safe
  // eslint-disable-next-line no-var
  var __CUSTOMERS__: Customer[] | undefined
}
const g = globalThis as any
if (!g.__CUSTOMERS__) {
  const now = () => new Date().toISOString()
  g.__CUSTOMERS__ = [
    { id: 'c_1001', name: 'Ola Nordmann',   email: 'ola@example.com',   phone: '40000001', createdAt: now() },
    { id: 'c_1002', name: 'Kari Nordmann',  email: 'kari@example.com',  phone: '40000002', createdAt: now() },
    { id: 'c_1003', name: 'Per Hansen',     email: 'per@example.com',   phone: '40000003', createdAt: now() },
    { id: 'c_1004', name: 'Anne Olsen',     email: 'anne@example.com',  phone: '40000004', createdAt: now() },
    { id: 'c_1005', name: 'Test Kunde',     email: 'test@example.com',  phone: '40000005', createdAt: now() },
  ]
}
const db = g.__CUSTOMERS__ as Customer[]

export function listCustomers(opts?: { q?: string; page?: number; size?: number }) {
  const q = (opts?.q ?? '').toLowerCase().trim()
  let rows = db
  if (q) {
    rows = rows.filter(c => {
      const hay = [c.id, c.name, c.email, c.phone].filter(Boolean).join(' ').toLowerCase()
      return hay.includes(q)
    })
  }
  const page = Math.max(1, opts?.page ?? 1)
  const size = Math.max(1, Math.min(500, opts?.size ?? 50))
  const start = (page - 1) * size
  const items = rows.slice(start, start + size)
  return { items, total: rows.length, page, size }
}

export function getCustomer(id: string) {
  return db.find(c => c.id === id) || null
}

export function createCustomer(input: CustomerInput) {
  const id = input.id || `c_${Math.random().toString(36).slice(2,10)}`
  const c: Customer = {
    id,
    name: input.name || 'Uten navn',
    email: input.email,
    phone: input.phone,
    createdAt: input.createdAt || new Date().toISOString(),
  }
  db.unshift(c)
  return c
}
TS

echo "→ Skriver app/api/customers/route.ts"
cat > "$ROOT/app/api/customers/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { listCustomers, createCustomer } from '@/src/lib/customers'

export const dynamic = 'force-dynamic'

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const q = searchParams.get('q') || undefined
  const page = Number(searchParams.get('page') || '1')
  const size = Number(searchParams.get('size') || '50')
  const out = listCustomers({ q, page, size })
  return NextResponse.json(out, { status: 200 })
}

export async function POST(req: Request) {
  const body = await req.json().catch(() => ({}))
  if (!body || typeof body !== 'object') {
    return NextResponse.json({ error: 'Invalid body' }, { status: 400 })
  }
  const c = createCustomer({
    id: body.id,
    name: body.name,
    email: body.email,
    phone: body.phone,
  })
  return NextResponse.json(c, { status: 201 })
}
TS

# (Valgfritt) Legg inn enkel favicon for å bli kvitt 404-støy i konsollen
if [ ! -f "$ROOT/public/favicon.ico" ]; then
  echo "→ Skriver public/favicon.ico (placeholder)"
  # 1x1 blank ico
  base64 -d > "$ROOT/public/favicon.ico" <<'B64'
AAABAAEAEBAAAAEAIABoAwAAFgAAACgAAAAQAAAAIAAAAAEAGAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64
fi

echo "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" >/dev/null 2>&1 || true
echo "✓ Ferdig. Start dev (npm run dev) og åpne /admin/customers"
