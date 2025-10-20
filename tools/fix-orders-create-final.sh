#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
LIB="$ROOT/src/lib/orders.ts"
CLIENT="$ROOT/app/admin/orders/new/OrderCreate.client.tsx"

say(){ printf "%s\n" "$*"; }

# --- 1) Skriv lib-funksjon med stabil eksport (named + default) ---
say "→ Skriver $LIB"
mkdir -p "$(dirname "$LIB")"
cat > "$LIB" <<'TS'
// NB: Ingen "use server" her – kan importeres fra klient.
export type CreateOrderPayload = {
  customer: any
  lines: Array<{ productId: string; variantId?: string; qty: number; price?: number }>
  notes?: string
}

export async function apiCreateOrder(payload: CreateOrderPayload): Promise<any> {
  const res = await fetch('/api/orders', {
    method: 'POST',
    headers: { 'Content-Type':'application/json' },
    body: JSON.stringify(payload),
    cache: 'no-store',
  })
  if (!res.ok) {
    let txt = ''
    try { txt = await res.text() } catch {}
    throw new Error(`HTTP ${res.status}${txt ? `: ${txt}` : ''}`)
  }
  return res.json()
}

export default apiCreateOrder
TS

# --- 2) Patch klient-komponenten med et lite Node-script (trygt på macOS) ---
if [ ! -f "$CLIENT" ]; then
  say "⚠️ Fant ikke $CLIENT – hopper over patch av klientfil."
else
  say "→ Patcher $CLIENT (imports/kall/duplikater)…"
  node - <<'NODE'
const fs = require('fs');
const path = require('path');

const client = path.resolve('app/admin/orders/new/OrderCreate.client.tsx');
let src = fs.readFileSync(client, 'utf8');

// — Fjern alle eksisterende imports av apiCreateOrder (named/default/* as)
src = src
  .replace(/^\s*import\s*\{[^}]*\bapiCreateOrder\b[^}]*\}\s*from\s*['"][^'"]+['"];\s*$/gm, '')
  .replace(/^\s*import\s+apiCreateOrder\s+from\s*['"][^'"]+['"];\s*$/gm, '')
  .replace(/^\s*import\s+\*\s+as\s+OrdersApi\s+from\s*['"][^'"]+['"];\s*$/gm, '');

// — Sett inn korrekt named import etter første import (eller på toppen)
const importLine = "import { apiCreateOrder } from '@/src/lib/orders'\n";
if (/^import\s/m.test(src)) {
  // etter første import-linje
  src = src.replace(/^import[^\n]*\n/, m => m + importLine);
} else {
  src = importLine + src;
}

// — Bytt ulike kall-varianter til apiCreateOrder(...)
src = src
  .replace(/\bOrdersApi\.apiCreateOrder\s*\(/g, 'apiCreateOrder(')
  .replace(/\bapiCreateOrderLocal\s*\(/g, 'apiCreateOrder(');

// — Fjern lokale definisjoner som kolliderer (function/const)
src = src
  .replace(/export\s+async\s+function\s+apiCreateOrder\s*\([^)]*\)\s*:\s*Promise<[^>]*>\s*\{[\s\S]*?\}\s*/g, '')
  .replace(/async\s+function\s+apiCreateOrder\s*\([^)]*\)\s*\{[\s\S]*?\}\s*/g, '')
  .replace(/const\s+apiCreateOrder\s*=\s*async\s*\([^)]*\)\s*=>\s*\{[\s\S]*?\}\s*;?/g, '');

// — Skriv tilbake
fs.writeFileSync(client, src, 'utf8');
console.log('✓ Klient patch’et');
NODE
fi

# --- 3) Rydd cache ---
say "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true

say "✓ Ferdig. Start dev-server på nytt (npm run dev) og test ordreopprettelse."