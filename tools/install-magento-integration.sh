#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"

say() { printf "%b\n" "→ $*"; }
ok()  { printf "%b\n" "✓ $*"; }
warn(){ printf "%b\n" "⚠ $*"; }
err(){ printf "%b\n" "✗ $*" 1>&2; }

# --- Sjekk env ---
if [ ! -f ".env.local" ]; then
  warn ".env.local mangler – oppretter tom fil"
  touch .env.local
fi

# Sørg for at base-variabler finnes (ikke overskriv verdier)
grep -q '^MAGENTO_BASE_URL=' .env.local || echo 'MAGENTO_BASE_URL=' >> .env.local
grep -q '^MAGENTO_ADMIN_TOKEN=' .env.local || echo 'MAGENTO_ADMIN_TOKEN=' >> .env.local
grep -q '^PRICE_MULTIPLIER=' .env.local || echo 'PRICE_MULTIPLIER=1' >> .env.local

say "Oppretter mapper…"
mkdir -p src/lib
mkdir -p app/api/products
mkdir -p app/api/customers
mkdir -p app/api/orders
mkdir -p app/api/products/[id]
mkdir -p app/api/customers/[id]

# ---------------------------
# src/lib/magento.ts
# ---------------------------
say "Skriver src/lib/magento.ts"
cat > src/lib/magento.ts <<'TS'
const BASE = process.env.MAGENTO_BASE_URL!;
const TOKEN = process.env.MAGENTO_ADMIN_TOKEN!;

if (!BASE || !TOKEN) {
  throw new Error('Missing MAGENTO_BASE_URL or MAGENTO_ADMIN_TOKEN in environment');
}

async function handle<T>(res: Response, verb: string, path: string): Promise<T> {
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Magento ${verb} ${path} -> ${res.status} ${text}`);
  }
  return res.json() as Promise<T>;
}

const headers: HeadersInit = {
  'Content-Type': 'application/json',
  'Authorization': `Bearer ${TOKEN}`,
};

export async function mgGet<T>(path: string) {
  const res = await fetch(`${BASE}${path}`, { headers, cache: 'no-store' });
  return handle<T>(res, 'GET', path);
}

export async function mgPost<T>(path: string, body?: any) {
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers,
    body: body ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  });
  return handle<T>(res, 'POST', path);
}

export async function mgPut<T>(path: string, body?: any) {
  const res = await fetch(`${BASE}${path}`, {
    method: 'PUT',
    headers,
    body: body ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  });
  return handle<T>(res, 'PUT', path);
}
TS

# ---------------------------
# src/lib/products.ts
# ---------------------------
say "Skriver src/lib/products.ts"
cat > src/lib/products.ts <<'TS'
import { mgGet } from './magento'

const MULT = parseFloat(process.env.PRICE_MULTIPLIER || '1') || 1

type MagentoProduct = {
  id: number
  sku: string
  name: string
  price?: number
  type_id?: string
  extension_attributes?: {
    stock_item?: { qty?: number }
    [k: string]: any
  }
  custom_attributes?: Array<{ attribute_code: string, value: any }>
}

export type ProductDTO = {
  id: number
  sku: string
  name: string
  price: number
  stock: number|null
  type?: string
  attributes?: Record<string, any>
}

function readCustomAttributes(p: MagentoProduct): Record<string, any> {
  const out: Record<string, any> = {}
  ;(p.custom_attributes||[]).forEach(a => { out[a.attribute_code] = a.value })
  return out
}

export function toProductDTO(p: MagentoProduct): ProductDTO {
  // pris-multiplikator for backend-kalkulasjon
  const base = p.price ?? 0
  const price = Math.round(base * MULT * 100) / 100
  const attrs = readCustomAttributes(p)
  const stock = p.extension_attributes?.stock_item?.qty ?? null
  return {
    id: p.id,
    sku: p.sku,
    name: p.name,
    price,
    stock: typeof stock === 'number' ? stock : null,
    type: p.type_id,
    attributes: attrs,
  }
}

export async function listProducts(paramsIn?: { page?: number, size?: number, q?: string }) {
  const page = paramsIn?.page ?? 1
  const size = paramsIn?.size ?? 50
  const q = (paramsIn?.q || '').trim()

  const params = new URLSearchParams()
  params.set('searchCriteria[currentPage]', String(page))
  params.set('searchCriteria[pageSize]', String(size))

  if (q) {
    params.set('searchCriteria[filterGroups][0][filters][0][field]', 'name')
    params.set('searchCriteria[filterGroups][0][filters][0][value]', `%${q}%`)
    params.set('searchCriteria[filterGroups][0][filters][0][condition_type]', 'like')

    params.set('searchCriteria[filterGroups][1][filters][0][field]', 'sku')
    params.set('searchCriteria[filterGroups][1][filters][0][value]', `%${q}%`)
    params.set('searchCriteria[filterGroups][1][filters][0][condition_type]', 'like')
  }

  const data = await mgGet<{ items: MagentoProduct[], total_count: number }>(`/V1/products?${params.toString()}`)
  return {
    items: data.items.map(toProductDTO),
    total: data.total_count,
    page, size,
  }
}

export async function getProductByIdOrSku(idOrSku: string | number) {
  if (typeof idOrSku === 'string' && /\D/.test(idOrSku)) {
    const p = await mgGet<MagentoProduct>(`/V1/products/${encodeURIComponent(idOrSku)}`)
    return toProductDTO(p)
  }
  const params = new URLSearchParams()
  params.set('searchCriteria[filterGroups][0][filters][0][field]', 'entity_id')
  params.set('searchCriteria[filterGroups][0][filters][0][value]', String(idOrSku))
  params.set('searchCriteria[filterGroups][0][filters][0][condition_type]', 'eq')
  const data = await mgGet<{ items: MagentoProduct[] }>(`/V1/products?${params.toString()}`)
  const p = data.items[0]
  return p ? toProductDTO(p) : null
}
TS

# ---------------------------
# src/lib/customers.ts
# ---------------------------
say "Skriver src/lib/customers.ts"
cat > src/lib/customers.ts <<'TS'
import { mgGet } from './magento'

type MagentoCustomer = {
  id: number
  firstname?: string
  lastname?: string
  email: string
  created_at?: string
  updated_at?: string
  addresses?: any[]
  custom_attributes?: Array<{ attribute_code: string, value: any }>
}

export type CustomerDTO = {
  id: number
  name: string
  email: string
  createdAt?: string
  updatedAt?: string
  addresses?: any[]
  attributes?: Record<string, any>
}

function readCustomAttributes(c: MagentoCustomer): Record<string, any> {
  const out: Record<string, any> = {}
  ;(c.custom_attributes||[]).forEach(a => { out[a.attribute_code] = a.value })
  return out
}

export function toCustomerDTO(c: MagentoCustomer): CustomerDTO {
  const name = [c.firstname, c.lastname].filter(Boolean).join(' ') || c.email
  return {
    id: c.id,
    name,
    email: c.email,
    createdAt: c.created_at,
    updatedAt: c.updated_at,
    addresses: c.addresses || [],
    attributes: readCustomAttributes(c),
  }
}

export async function listCustomers(paramsIn?: { page?: number, size?: number, q?: string }) {
  const page = paramsIn?.page ?? 1
  const size = paramsIn?.size ?? 50
  const q = (paramsIn?.q || '').trim()

  const params = new URLSearchParams()
  params.set('searchCriteria[currentPage]', String(page))
  params.set('searchCriteria[pageSize]', String(size))

  if (q) {
    params.set('searchCriteria[filterGroups][0][filters][0][field]', 'email')
    params.set('searchCriteria[filterGroups][0][filters][0][value]', `%${q}%`)
    params.set('searchCriteria[filterGroups][0][filters][0][condition_type]', 'like')

    params.set('searchCriteria[filterGroups][1][filters][0][field]', 'firstname')
    params.set('searchCriteria[filterGroups][1][filters][0][value]', `%${q}%`)
    params.set('searchCriteria[filterGroups][1][filters][0][condition_type]', 'like')

    params.set('searchCriteria[filterGroups][2][filters][0][field]', 'lastname')
    params.set('searchCriteria[filterGroups][2][filters][0][value]', `%${q}%`)
    params.set('searchCriteria[filterGroups][2][filters][0][condition_type]', 'like')
  }

  const data = await mgGet<{ items: MagentoCustomer[], total_count: number }>(`/V1/customers/search?${params.toString()}`)
  return {
    items: data.items.map(toCustomerDTO),
    total: data.total_count,
    page, size,
  }
}

export async function getCustomer(id: number) {
  const c = await mgGet<MagentoCustomer>(`/V1/customers/${id}`)
  return toCustomerDTO(c)
}
TS

# ---------------------------
# src/lib/orders.magento.ts
# ---------------------------
say "Skriver src/lib/orders.magento.ts"
cat > src/lib/orders.magento.ts <<'TS'
import { mgPost, mgPut } from './magento'

export async function createGuestCart() {
  return mgPost<string>('/V1/guest-carts')
}

export async function addItemsToGuestCart(cartId: string, items: Array<{sku: string, qty: number}>) {
  // Magento API for items expects one at a time, men Magento godtar også array via cartItem? Variasjoner forekommer.
  for (const i of items) {
    await mgPost(`/V1/guest-carts/${cartId}/items`, {
      cartItem: {
        sku: i.sku,
        qty: i.qty,
        quote_id: cartId,
      }
    })
  }
}

export async function setGuestCartAddresses(cartId: string, address: any) {
  return mgPost(`/V1/guest-carts/${cartId}/shipping-information`, {
    addressInformation: {
      shipping_address: address,
      billing_address: address,
      shipping_carrier_code: 'flatrate',
      shipping_method_code: 'flatrate',
    }
  })
}

export async function placeGuestOrder(cartId: string, paymentMethodCode = 'checkmo') {
  await mgPut(`/V1/guest-carts/${cartId}/selected-payment-method`, {
    method: { method: paymentMethodCode }
  })
  return mgPost<number>(`/V1/guest-carts/${cartId}/order`)
}
TS

# ---------------------------
# src/lib/orders.ts (adapter for UI)
# ---------------------------
say "Skriver src/lib/orders.ts"
cat > src/lib/orders.ts <<'TS'
import { createGuestCart, addItemsToGuestCart, setGuestCartAddresses, placeGuestOrder } from './orders.magento'

export type OrderCustomer = {
  email: string
  firstname?: string
  lastname?: string
  phone?: string
  address?: { street?: string, city?: string, postcode?: string, countryId?: string }
}

export type OrderLine = { sku: string, name?: string, qty: number, price?: number }

export async function apiCreateOrder(payload: { customer: OrderCustomer, lines: OrderLine[], notes?: string }) {
  const cartId = await createGuestCart()

  await addItemsToGuestCart(cartId, payload.lines.map(l => ({ sku: l.sku, qty: l.qty })))

  const addr = {
    email: payload.customer.email,
    firstname: payload.customer.firstname || 'N/A',
    lastname: payload.customer.lastname || 'N/A',
    street: [payload.customer.address?.street || 'N/A'],
    city: payload.customer.address?.city || 'N/A',
    postcode: payload.customer.address?.postcode || '0000',
    countryId: payload.customer.address?.countryId || 'NO',
    telephone: payload.customer.phone || '00000000',
  }
  await setGuestCartAddresses(cartId, addr)

  const orderId = await placeGuestOrder(cartId)
  return { id: String(orderId) }
}
TS

# ---------------------------
# API routes
# ---------------------------
say "Skriver app/api/products/route.ts (GET)"
cat > app/api/products/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { listProducts } from '@/src/lib/products'

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = parseInt(searchParams.get('page') || '1', 10)
  const size = parseInt(searchParams.get('size') || '50', 10)
  const q = searchParams.get('q') || ''
  try {
    const out = await listProducts({ page, size, q })
    return NextResponse.json(out)
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Failed to fetch products' }, { status: 400 })
  }
}
TS

say "Skriver app/api/products/[id]/route.ts (GET by id/sku)"
cat > app/api/products/[id]/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getProductByIdOrSku } from '@/src/lib/products'

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params
  try {
    const p = await getProductByIdOrSku(isNaN(Number(id)) ? id : Number(id))
    if (!p) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    return NextResponse.json(p)
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Failed' }, { status: 400 })
  }
}
TS

say "Skriver app/api/customers/route.ts (GET)"
cat > app/api/customers/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { listCustomers } from '@/src/lib/customers'

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = parseInt(searchParams.get('page') || '1', 10)
  const size = parseInt(searchParams.get('size') || '50', 10)
  const q = searchParams.get('q') || ''
  try {
    const out = await listCustomers({ page, size, q })
    return NextResponse.json(out)
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Failed to fetch customers' }, { status: 400 })
  }
}
TS

say "Skriver app/api/customers/[id]/route.ts (GET)"
cat > app/api/customers/[id]/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getCustomer } from '@/src/lib/customers'

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params
  try {
    const c = await getCustomer(Number(id))
    return NextResponse.json(c)
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Failed' }, { status: 400 })
  }
}
TS

say "Skriver/oppdaterer app/api/orders/route.ts (POST create)"
cat > app/api/orders/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { apiCreateOrder } from '@/src/lib/orders'

export async function POST(req: Request) {
  try {
    const payload = await req.json()
    const out = await apiCreateOrder(payload)
    return NextResponse.json(out, { status: 201 })
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Order create failed' }, { status: 400 })
  }
}
TS

# ---------------------------
# Rydd cache-hint
# ---------------------------
say "Rydder .next-cache"
rm -rf .next 2>/dev/null || true
rm -rf .next-cache 2>/dev/null || true

ok "Ferdig! Start dev-server på nytt (npm run dev / yarn dev / pnpm dev)."
echo
echo "Tips:"
echo "  - Legg inn pris-multiplikator i .env.local (PRICE_MULTIPLIER=1.15 f.eks)."
echo "  - Endre frakt/payment-koder i src/lib/orders.magento.ts hvis nødvendig."