#!/usr/bin/env bash
set -euo pipefail

root_dir="$(pwd)"
lib_file="$root_dir/src/lib/orders.ts"
client_file="$root_dir/app/admin/orders/new/OrderCreate.client.tsx"

say(){ printf "%s\n" "$*"; }

say "→ Oppretter mappe for lib (om nødvendig)"
mkdir -p "$(dirname "$lib_file")"

say "→ Skriver $lib_file (named + default export av funksjon)"
cat > "$lib_file" <<'TS'
export type CreateOrderPayload = {
  customer: any
  lines: Array<{ productId: string; variantId?: string; qty: number; price?: number }>
  notes?: string
}

/**
 * Klientkall mot POST /api/orders
 * - Named export: apiCreateOrder
 * - Default export: apiCreateOrder (samme funksjon)
 */
const apiCreateOrderImpl = async (payload: CreateOrderPayload): Promise<any> => {
  const res = await fetch('/api/orders', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
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

export const apiCreateOrder = apiCreateOrderImpl
export default apiCreateOrderImpl
TS

if [ ! -f "$client_file" ]; then
  say "⚠️ Fant ikke $client_file – hopper patch av klientfil."
else
  say "→ Patcher import i $client_file til namespace (unngår navnekollisjon)"
  tmp="$(mktemp)"

  # 1) Fjern ALLE eksisterende imports av apiCreateOrder (default eller named)
  # (Mac/BSD sed krever -E uten -r)
  sed -E '/^import .*apiCreateOrder.*from /d' "$client_file" > "$tmp"
  mv "$tmp" "$client_file"

  # 2) Sett inn namespace-import rett etter første import-linje (eller på toppen)
  first_import_line="$(grep -n '^import ' "$client_file" | head -n1 | cut -d: -f1 || true)"
  tmp="$(mktemp)"
  if [ -n "$first_import_line" ]; then
    awk -v L="$first_import_line" 'NR==L{print; print "import * as OrdersApi from '\''@/src/lib/orders'\''"; next}1' "$client_file" > "$tmp"
  else
    { echo "import * as OrdersApi from '@/src/lib/orders'"; cat "$client_file"; } > "$tmp"
  fi
  mv "$tmp" "$client_file"

  # 3) Erstatt direkte kall til apiCreateOrder( … ) -> OrdersApi.apiCreateOrder( … )
  #   (Både med og uten mellomrom før parantes.)
  perl -i -pe 's/\bapiCreateOrder\s*\(/OrdersApi.apiCreateOrder(/g' "$client_file"

  # 4) Hvis det finnes en LOKAL definisjon/const/function apiCreateOrder, rename til Local
  perl -i -pe 's/\bexport\s+async\s+function\s+apiCreateOrder\b/export async function apiCreateOrderLocal/g' "$client_file" || true
  perl -i -pe 's/\basync\s+function\s+apiCreateOrder\b/async function apiCreateOrderLocal/g' "$client_file" || true
  perl -i -pe 's/\bconst\s+apiCreateOrder\s*=\s*async/const apiCreateOrderLocal = async/g' "$client_file" || true
  perl -i -pe 's/\bfunction\s+apiCreateOrder\s*\(/function apiCreateOrderLocal(/g' "$client_file" || true
fi

say "→ Rydder Next-cache"
rm -rf "$root_dir/.next" "$root_dir/.next-cache" 2>/dev/null || true

say "✓ Ferdig. Start dev-server på nytt (npm run dev) og test opprett ordre."