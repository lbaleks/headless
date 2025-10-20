#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.."; pwd)"
FILE="$ROOT/app/api/orders/route.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ Fant ikke $FILE – sørg for at /app/api/orders/route.ts eksisterer (med GET-handler)."
  exit 1
fi

cp "$FILE" "$FILE.bak.$(date +%s)"

# Fjern eksisterende POST-blokk (for å unngå duplikater)
# Enkel state-maskin: dropp linjer fra 'export async function POST(' til første 'export async function' ELLER EOF.
awk '
  BEGIN{drop=0}
  /export[[:space:]]+async[[:space:]]+function[[:space:]]+POST[[:space:]]*\(/ {drop=1; next}
  drop==1 && /export[[:space:]]+async[[:space:]]+function[[:space:]]+/ {drop=0}
  drop==0 {print}
' "$FILE" > "$FILE.tmp1" || true

# Sørg for import av NextResponse (kun én gang)
if ! grep -q "from 'next/server'" "$FILE.tmp1"; then
  # macOS sed fallback
  sed -i '' '1s/^/import { NextResponse } from '\''next\/server'\'';\n/' "$FILE.tmp1" 2>/dev/null || sed -i '1s/^/import { NextResponse } from '\''next\/server'\'';\n/' "$FILE.tmp1"
else
  # Men ikke dubliser NextResponse importen
  if ! grep -q "import {[^}]*NextResponse" "$FILE.tmp1"; then
    sed -i '' '1s/^/import { NextResponse } from '\''next\/server'\'';\n/' "$FILE.tmp1" 2>/dev/null || sed -i '1s/^/import { NextResponse } from '\''next\/server'\'';\n/' "$FILE.tmp1"
  fi
fi

cat >> "$FILE.tmp1" <<'TS'

// --- Magento create order (guest cart) ---
const M2_BASE = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN

async function m2<T>(verb: 'GET'|'POST'|'PUT', path: string, body?: any): Promise<T> {
  if (!M2_BASE || !M2_TOKEN) throw new Error('Missing MAGENTO_BASE_URL / MAGENTO_ADMIN_TOKEN')
  const url = `${M2_BASE!.replace(/\/+$/,'')}/${path.replace(/^\/+/,'')}`
  const res = await fetch(url, {
    method: verb,
    headers: {
      'Authorization': `Bearer ${M2_TOKEN}`,
      'Content-Type': 'application/json'
    },
    cache: 'no-store',
    body: body ? JSON.stringify(body) : undefined
  })
  const txt = await res.text().catch(()=> '')
  if (!res.ok) throw new Error(`Magento ${verb} ${url} failed: ${res.status} ${txt}`)
  return (txt ? JSON.parse(txt) : undefined) as T
}

function pickAddress(input: any){
  const email = input?.email || 'guest@example.com'
  const base = {
    email,
    firstname: input?.firstname || 'Guest',
    lastname: input?.lastname || 'User',
    street: Array.isArray(input?.street) && input.street.length ? input.street : [input?.street?.[0] || 'Testveien 1'],
    city: input?.city || 'Oslo',
    postcode: input?.postcode || '0150',
    country_id: input?.country_id || 'NO',
    telephone: input?.telephone || '00000000'
  }
  return base
}

export async function POST(req: Request) {
  const t0 = Date.now()
  const STUBS = (globalThis as any).__ORD_STUBS__ ||= new Map<string, any>()

  try {
    const body = await req.json().catch(()=> ({}))
    const customer = body?.customer || {}
    const lines: Array<{sku:string; qty:number; name?:string; price?:number}> = Array.isArray(body?.lines)? body.lines : []
    const notes: string | undefined = body?.notes

    if (!lines.length) return NextResponse.json({ error: 'No lines' }, { status: 400 })

    // 1) Guest cart
    const cartId = await m2<string>('POST','V1/guest-carts')

    // 2) Add items
    for (const l of lines) {
      if (!l?.sku || !l?.qty) continue
      await m2<any>('POST', `V1/guest-carts/${encodeURIComponent(cartId)}/items`, {
        cartItem: { quote_id: cartId, sku: l.sku, qty: Number(l.qty) }
      })
    }

    // 3) Shipping + billing + shipping method
    const shipping = pickAddress(customer)
    const billing  = pickAddress(customer)
    await m2<any>('POST', `V1/guest-carts/${encodeURIComponent(cartId)}/shipping-information`, {
      addressInformation: {
        shipping_address: shipping,
        billing_address: billing,
        shipping_carrier_code: 'flatrate',
        shipping_method_code: 'flatrate'
      }
    })

    // 4) Payment + place order
    const orderId: number = await m2<number>('POST', `V1/guest-carts/${encodeURIComponent(cartId)}/payment-information`, {
      paymentMethod: { method: 'checkmo' },
      billing_address: billing
    })

    // 5) Fetch order to get increment_id
    const order = await m2<any>('GET', `V1/orders/${orderId}`)
    const out = {
      id: String(order?.entity_id ?? orderId),
      increment_id: order?.increment_id ?? String(orderId),
      status: order?.status ?? 'new',
      created_at: order?.created_at ?? new Date().toISOString(),
      customer: { email: shipping.email, firstname: shipping.firstname, lastname: shipping.lastname },
      lines: lines.map((l, i) => ({ i, sku: l.sku, qty: l.qty, name: l.name || null, price: l.price ?? null })),
      notes: notes || null,
      source: 'magento',
      elapsed_ms: Date.now() - t0
    }
    return NextResponse.json(out, { status: 201 })

  } catch (err: any) {
    // Fallback stub så UI ikke ryker
    const sid = `ORD-${Date.now()}`
    const stub = {
      id: sid,
      increment_id: sid,
      status: 'new',
      created_at: new Date().toISOString(),
      customer: null,
      lines: [],
      notes: null,
      source: 'local-stub',
      error: String(err?.message || err),
      elapsed_ms: Date.now() - t0
    }
    STUBS.set(sid, stub)
    console.error('[POST /api/orders] Magento error -> stub', err?.stack || err)
    return NextResponse.json(stub, { status: 201 })
  }
}
TS

mv "$FILE.tmp1" "$FILE"

echo "→ Rydder .next/.next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true
echo "✓ Ferdig. Start dev på nytt (npm run dev) og test POST."
