#!/usr/bin/env bash
set -euo pipefail

# --- paths ---
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAR_DIR="$ROOT/var"
STORE_JSON="$VAR_DIR/orders.dev.json"
ORDERS_ROUTE="$ROOT/app/api/orders/route.ts"

# --- seed endpoint (debug) ---
SEED_DIR="$ROOT/app/api/_debug/orders"
SEED_ROUTE="$SEED_DIR/route.ts"

echo "→ Sikrer var/-mappe og dev store…"
mkdir -p "$VAR_DIR"
if [ ! -s "$STORE_JSON" ]; then
  echo "[]" > "$STORE_JSON"
  echo "  opprettet $STORE_JSON"
else
  echo "  fant $STORE_JSON"
fi

echo "→ Legger til DELETE-handler i $ORDERS_ROUTE (idempotent)…"
if ! grep -qE 'export\s+async\s+function\s+DELETE' "$ORDERS_ROUTE"; then
  cat >> "$ORDERS_ROUTE" <<'TS'

// ---- DEV-OPS: DELETE /api/orders?id=<id|all>  ----
export async function DELETE(req: Request) {
  try {
    const { searchParams } = new URL(req.url)
    const id = searchParams.get('id')
    const fs = await import('fs/promises')
    const p = `${process.cwd()}/var/orders.dev.json`
    const raw = await fs.readFile(p, 'utf8').catch(()=>'[]')
    const arr = JSON.parse(raw || '[]')
    let next = arr
    if (id && id !== 'all') {
      next = arr.filter((o: any)=> (o.id || o.increment_id) !== id)
    } else if (id === 'all') {
      next = []
    }
    await fs.writeFile(p, JSON.stringify(next, null, 2))
    return NextResponse.json({ ok:true, total: next.length })
  } catch (e:any) {
    console.error('DELETE orders failed', e)
    return NextResponse.json({ ok:false, error: e?.message || 'unknown' }, { status: 500 })
  }
}
TS
  echo "  la til DELETE-handler"
else
  echo "  DELETE-handler finnes allerede – hopper over."
fi

echo "→ Oppretter debug seed-endepunkt (idempotent)…"
mkdir -p "$SEED_DIR"
if [ ! -f "$SEED_ROUTE" ]; then
  cat > "$SEED_ROUTE" <<'TS'
import { NextResponse } from 'next/server'

type Line = { sku: string, name: string, qty: number, price: number, rowTotal: number }
type DevOrder = {
  id: string, increment_id: string, status: string, created_at: string,
  customer: { email: string, firstname?: string, lastname?: string },
  lines: Line[], notes?: string, total: number, source: 'local-stub'
}

function mk(idNum:number): DevOrder {
  const id = `ORD-${Date.now()}-${idNum}`
  const qty = (idNum % 3) + 1
  const price = 199 + (idNum % 4) * 50
  const line = { sku:'TEST', name:'TEST', qty, price, rowTotal: qty*price }
  return {
    id, increment_id: id, status: 'new', created_at: new Date().toISOString(),
    customer: { email:`dev+${idNum}@example.com` },
    lines: [line], notes:'seed', total: line.rowTotal, source:'local-stub'
  }
}

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const n = Math.max(1, Math.min(100, parseInt(searchParams.get('n') || '5', 10) || 5))
  const fs = await import('fs/promises')
  const p = `${process.cwd()}/var/orders.dev.json`
  const raw = await fs.readFile(p, 'utf8').catch(()=> '[]')
  const arr: DevOrder[] = JSON.parse(raw || '[]')
  const add = Array.from({length:n}, (_,i)=> mk(i+1))
  const next = [...add, ...arr]
  await fs.writeFile(p, JSON.stringify(next, null, 2))
  return NextResponse.json({ ok:true, seeded: n, total: next.length })
}
TS
  echo "  skrev $SEED_ROUTE"
else
  echo "  seed-endepunkt finnes allerede – hopper over."
fi

echo "✓ Ferdig. Start dev på nytt: npm run dev"
echo "  Test: curl -s 'http://localhost:3000/api/_debug/orders?n=3' | jq ."
