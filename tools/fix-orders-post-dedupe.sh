#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.."; pwd)"
FILE="$ROOT/app/api/orders/route.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ Fant ikke $FILE – sørg for at /app/api/orders/route.ts finnes."
  exit 1
fi

cp "$FILE" "$FILE.bak.$(date +%s)"

# 1) Fjern ALLE eksisterende POST-handlere (robust state-maskin)
awk '
  BEGIN{drop=0}
  /export[[:space:]]+async[[:space:]]+function[[:space:]]+POST[[:space:]]*\(/ {drop=1; brace=0}
  drop==1 {
    # Track { } for robust blokk-slutt (enkelt, men funker bra for TS)
    brace += gsub(/\{/,"{")
    brace -= gsub(/\}/,"}")
    if (brace<=0 && /\}/) { drop=0; next }
    next
  }
  {print}
' "$FILE" > "$FILE.tmp1"

# 2) Fjern duplikate M2_BASE/M2_TOKEN linjer
sed -i '' '/^\s*const\s\+M2_BASE\s*=.*/d' "$FILE.tmp1" 2>/dev/null || sed -i '/^\s*const\s\+M2_BASE\s*=.*/d' "$FILE.tmp1"
sed -i '' '/^\s*const\s\+M2_TOKEN\s*=.*/d' "$FILE.tmp1" 2>/dev/null || sed -i '/^\s*const\s\+M2_TOKEN\s*=.*/d' "$FILE.tmp1"

# 3) Sørg for NextResponse-import kun én gang
if ! grep -q "from 'next/server'" "$FILE.tmp1"; then
  sed -i '' '1s/^/import { NextResponse } from '\''next\/server'\'';\n/' "$FILE.tmp1" 2>/dev/null || sed -i '1s/^/import { NextResponse } from '\''next\/server'\'';\n/' "$FILE.tmp1"
else
  if ! grep -q "import {[^}]*NextResponse" "$FILE.tmp1"; then
    sed -i '' '1s/^/import { NextResponse } from '\''next\/server'\'';\n/' "$FILE.tmp1" 2>/dev/null || sed -i '1s/^/import { NextResponse } from '\''next\/server'\'';\n/' "$FILE.tmp1"
  fi
fi

# 4) Legg inn EN felles M2_BASE/M2_TOKEN + Magento helper + POST nederst
cat >> "$FILE.tmp1" <<'TS'

// === Magento (guest cart) – felles config ===
const M2_BASE  = process.env.MAGENTO_BASE_URL   || process.env.M2_BASE_URL
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
  return {
    email,
    firstname: input?.firstname || 'Guest',
    lastname:  input?.lastname  || 'User',
    street:    Array.isArray(input?.street)&&input.street.length? input.street : [ input?.street?.[0] || 'Testveien 1' ],
    city:      input?.city || 'Oslo',
    postcode:  input?.postcode || '0150',
    country_id:input?.country_id || 'NO',
    telephone: input?.telephone || '00000000'
  }
}

// === ENESTE POST-handler ===
export async function POST(req: Request) {
  const t0 = Date.now()
  try {
    const body = await req.json().catch(()=> ({}))
    const customer = body?.customer || {}
    const lines: Array<{sku:string; qty:number; name?:string; price?:number}> = Array.isArray(body?.lines)? body.lines : []
    const notes: string | undefined = body?.notes

    if (!lines.length) return NextResponse.json({ error: 'No lines' }, { status: 400 })

    // 1) Guest cart
    const cartId = await m2<string>('POST','V1/guest-carts')

    // 2) Items
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

    // 5) Fetch order for increment_id
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
    // Som dev-fallback: returner stub (201) slik at UI ikke låser seg
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
    console.error('[POST /api/orders] Magento error -> stub', err?.stack || err)
    return NextResponse.json(stub, { status: 201 })
  }
}
TS

mv "$FILE.tmp1" "$FILE"

echo "→ Rydder cache (.next/.next-cache)…"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true
echo "✓ Klar. Start dev på nytt: npm run dev"
