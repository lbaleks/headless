#!/usr/bin/env bash
set -euo pipefail

# macOS/BSD vs GNU sed kompatibelt -i
sedi() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

root_dir="$(pwd)"

echo "→ Oppretter mapper hvis de mangler…"
mkdir -p "$root_dir/src/lib"
mkdir -p "$root_dir/app/api/orders"
mkdir -p "$root_dir/tools"

###############################################################################
# 1) src/lib/orders.ts  — named export: apiCreateOrder
###############################################################################
lib_orders="$root_dir/src/lib/orders.ts"
echo "→ Skriver $lib_orders"
cat > "$lib_orders" <<'TS'
export async function apiCreateOrder(args: { customer: any; lines: any[]; notes?: string }) {
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

###############################################################################
# 2) app/api/orders/route.ts  — sørg for POST-handler
###############################################################################
api_route="$root_dir/app/api/orders/route.ts"
if [ ! -f "$api_route" ]; then
  echo "→ Lager $api_route med POST-handler"
  cat > "$api_route" <<'TS'
import { NextResponse } from 'next/server'

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}))
  const now = new Date().toISOString()
  const id = (globalThis.crypto as any)?.randomUUID?.() || Math.random().toString(36).slice(2)

  const order = {
    id,
    customer: body.customer ?? null,
    lines: Array.isArray(body.lines) ? body.lines : [],
    notes: body.notes ?? '',
    status: 'new',
    createdAt: now,
    updatedAt: now,
  }

  return NextResponse.json(order, { status: 201 })
}
TS
else
  echo "→ Fant $api_route – sjekker om POST finnes…"
  if ! grep -qE 'export\s+async\s+function\s+POST' "$api_route"; then
    echo "→ Legger til POST-handler nederst i $api_route"
    cat >> "$api_route" <<'TS'

import { NextResponse } from 'next/server'

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}))
  const now = new Date().toISOString()
  const id = (globalThis.crypto as any)?.randomUUID?.() || Math.random().toString(36).slice(2)

  const order = {
    id,
    customer: body.customer ?? null,
    lines: Array.isArray(body.lines) ? body.lines : [],
    notes: body.notes ?? '',
    status: 'new',
    createdAt: now,
    updatedAt: now,
  }

  return NextResponse.json(order, { status: 201 })
}
TS
  else
    echo "→ POST-handler finnes allerede – hopper over."
  fi
fi

###############################################################################
# 3) Patch: app/admin/orders/new/OrderCreate.client.tsx
#    - riktig import { apiCreateOrder } from '@/src/lib/orders'
#    - fjern ev. gamle/feile imports
#    - IKKE behold lokal skygge-const apiCreateOrder
###############################################################################
create_client="$root_dir/app/admin/orders/new/OrderCreate.client.tsx"
if [ -f "$create_client" ]; then
  echo "→ Patcher $create_client (imports og kall)…"

  # Fjern eksisterende apiCreateOrder-imports (uansett path)
  sedi '/import\s\{[^}]*apiCreateOrder[^}]*\}\sfrom\s*[^\;]*;$/d' "$create_client"

  # Sett inn korrekt import etter første import-linje
  first_import_line=$(grep -n '^import ' "$create_client" | head -n1 | cut -d: -f1 || echo "")
  if [ -n "$first_import_line" ]; then
    tmpfile="$(mktemp)"
    awk -v line="$first_import_line" 'NR==line{print; print "import { apiCreateOrder } from '\''@/src/lib/orders'\''"; next}1' "$create_client" > "$tmpfile"
    mv "$tmpfile" "$create_client"
  else
    # Fila starter uten imports – prepender
    tmpfile="$(mktemp)"
    { echo "import { apiCreateOrder } from '@/src/lib/orders'"; cat "$create_client"; } > "$tmpfile"
    mv "$tmpfile" "$create_client"
  fi

  # Erstatt ev. kall til createOrder(...) -> apiCreateOrder(...)
  sedi 's/\bcreateOrder\s*\(/apiCreateOrder(/g' "$create_client"

  # Fjern lokal definisjon som kan skygge importen (konservativ: kun enkel-linje const)
  sedi '/^\s*const\s\+apiCreateOrder\s*=.*/d' "$create_client"
else
  echo "⚠️  Fant ikke $create_client – hopper over patch av klientfil."
fi

###############################################################################
# 4) Rydd cache-hint
###############################################################################
echo "→ Rydder .next-cache hint (valgfritt)"
rm -rf "$root_dir/.next" 2>/dev/null || true
rm -rf "$root_dir/.next-cache" 2>/dev/null || true

echo "✓ Ferdig. Start dev-server på nytt (npm run dev)."