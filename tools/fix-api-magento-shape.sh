#!/usr/bin/env bash
set -euo pipefail

echo "→ Oppretter mapper…"
mkdir -p src/lib app/api/products app/api/customers app/api/orders

echo "→ Skriver src/lib/m2client.ts"
cat > src/lib/m2client.ts <<'TS'
// Minimal Magento client uavhengig av annen lokal kode.
const BASE = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL
if (!BASE) throw new Error('MAGENTO_BASE_URL (eller M2_BASE_URL) mangler')

function adminToken(): string {
  // Støtt både .env-token og runtime (auto-login) token
  const t = process.env.MAGENTO_ADMIN_TOKEN || (globalThis as any).__M2_TOKEN
  if (!t) throw new Error('MAGENTO_ADMIN_TOKEN er ikke tilgjengelig (prøv å refreshe dev / sjekk /api/_debug/ping)')
  return t
}

export async function m2Get<T>(path: string): Promise<T> {
  const url = `${BASE.replace(/\/+$/,'')}/${path.replace(/^\/+/,'')}`
  const res = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${adminToken()}`,
      'Content-Type': 'application/json',
    },
    // Viktig i Next 15 for å ikke cache admin-lister
    cache: 'no-store',
  })
  if (!res.ok) {
    let body: any = undefined
    try { body = await res.json() } catch {}
    throw new Error(`Magento GET ${url} failed: ${res.status} ${body?JSON.stringify(body):''}`.trim())
  }
  return res.json() as Promise<T>
}

// Små hjelpere for paginering
export function parsePaging(req: Request) {
  const u = new URL(req.url)
  const page = Math.max(1, parseInt(u.searchParams.get('page') || '1', 10))
  const size = Math.max(1, Math.min(200, parseInt(u.searchParams.get('size') || '50', 10)))
  return { page, size }
}
TS

echo "→ Skriver app/api/products/route.ts"
cat > app/api/products/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { m2Get, parsePaging } from '@/src/lib/m2client'

type MagentoProductList = { items: any[]; total_count: number }

function mapProduct(p: any) {
  // En lettvekts visningsmodell – utvid når vi trenger mer
  const ca = Object.fromEntries((p.custom_attributes||[]).map((a:any)=>[a.attribute_code,a.value]))
  return {
    id: p.id,
    sku: p.sku,
    name: p.name,
    price: p.price,
    status: p.status,
    visibility: p.visibility,
    type: p.type_id,
    created_at: p.created_at,
    updated_at: p.updated_at,
    image: ca.image || ca.small_image || ca.thumbnail || null,
  }
}

export async function GET(req: Request) {
  try {
    const { page, size } = parsePaging(req)
    const data = await m2Get<MagentoProductList>(`V1/products?searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}`)
    const items = (data?.items || []).map(mapProduct)
    const total = data?.total_count ?? 0
    return NextResponse.json({ items, total, page, size })
  } catch (err:any) {
    return NextResponse.json({ items: [], total: 0, error: String(err?.message||err) }, { status: 400 })
  }
}
TS

echo "→ Skriver app/api/customers/route.ts"
cat > app/api/customers/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { m2Get, parsePaging } from '@/src/lib/m2client'

type MagentoCustomerList = { items: any[]; total_count: number }

function mapCustomer(c:any) {
  return {
    id: c.id,
    email: c.email,
    firstname: c.firstname,
    lastname: c.lastname,
    group_id: c.group_id,
    created_at: c.created_at,
    updated_at: c.updated_at,
    // legg til adresseuttrekk senere ved behov
  }
}

export async function GET(req: Request) {
  try {
    const { page, size } = parsePaging(req)
    const data = await m2Get<MagentoCustomerList>(`V1/customers/search?searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}`)
    const items = (data?.items || []).map(mapCustomer)
    const total = data?.total_count ?? 0
    return NextResponse.json({ items, total, page, size })
  } catch (err:any) {
    return NextResponse.json({ items: [], total: 0, error: String(err?.message||err) }, { status: 400 })
  }
}
TS

echo "→ Skriver app/api/orders/route.ts (GET liste – POST røres ikke her)"
cat > app/api/orders/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { m2Get, parsePaging } from '@/src/lib/m2client'

type MagentoOrderList = { items: any[]; total_count: number }

function mapOrder(o:any) {
  return {
    id: o.entity_id,
    increment_id: o.increment_id,
    status: o.status,
    state: o.state,
    created_at: o.created_at,
    updated_at: o.updated_at,
    customer_email: o.customer_email,
    customer_firstname: o.customer_firstname,
    customer_lastname: o.customer_lastname,
    grand_total: o.grand_total,
    currency: o.order_currency_code,
    total_item_count: o.total_item_count,
  }
}

export async function GET(req: Request) {
  try {
    const { page, size } = parsePaging(req)
    // Sorter nyeste først (created_at DESC)
    const path = [
      `V1/orders?searchCriteria[currentPage]=${page}`,
      `searchCriteria[pageSize]=${size}`,
      `searchCriteria[sortOrders][0][field]=created_at`,
      `searchCriteria[sortOrders][0][direction]=DESC`
    ].join('&')
    const data = await m2Get<MagentoOrderList>(path)
    const items = (data?.items || []).map(mapOrder)
    const total = data?.total_count ?? 0
    return NextResponse.json({ items, total, page, size })
  } catch (err:any) {
    return NextResponse.json({ items: [], total: 0, error: String(err?.message||err) }, { status: 400 })
  }
}
TS

echo "→ Rydder .next/.next-cache…"
rm -rf .next .next-cache 2>/dev/null || true

echo "✓ Ferdig. Start dev på nytt: npm run dev"
echo "  Test: curl -s 'http://localhost:3000/api/products?page=1&size=25' | jq '.total,(.items[0]//{}).sku'"
echo "        curl -s 'http://localhost:3000/api/customers?page=1&size=25' | jq '.total,(.items[0]//{}).email'"
echo "        curl -s 'http://localhost:3000/api/orders?page=1&size=25'    | jq '.total,(.items[0]//{}).increment_id'"
